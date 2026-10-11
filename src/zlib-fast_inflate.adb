with Ada.Unchecked_Deallocation;
with Interfaces;

package body Zlib.Fast_Inflate is

   use Interfaces;

   --  Anything that makes the stream one this decoder will not finish.
   Declined : exception;

   Fast_Bits : constant := 10;

   type Count_Array is array (0 .. 15) of Natural;
   type Symbol_Array is array (0 .. 319) of Natural;
   type Fast_Array is array (0 .. 2 ** Fast_Bits - 1) of Unsigned_16;

   --  A canonical Huffman code: how many codes of each length, its symbols
   --  in code order, and for each ten-bit window of input the symbol and
   --  length of the code it begins with -- zero where that code is longer.
   type Code is record
      Count  : Count_Array := [others => 0];
      Symbol : Symbol_Array := [others => 0];
      Fast   : Fast_Array := [others => 0];
   end record;

   type Length_Array is array (Natural range <>) of Natural;

   procedure Build (Item : out Code; Lengths : Length_Array) is
      Offsets : array (1 .. 15) of Natural;
      Left    : Integer := 1;
      Next    : Natural := 0;
   begin
      Item.Count := [others => 0];
      Item.Fast := [others => 0];
      for L of Lengths loop
         Item.Count (L) := Item.Count (L) + 1;
      end loop;
      --  Over-subscribed: no code. Incomplete is allowed, as zlib allows
      --  it; a code that is not there is met only if the data uses it.
      for Len in 1 .. 15 loop
         Left := Left * 2 - Item.Count (Len);
         if Left < 0 then
            raise Declined;
         end if;
      end loop;
      Offsets (1) := 0;
      for Len in 1 .. 14 loop
         Offsets (Len + 1) := Offsets (Len) + Item.Count (Len);
      end loop;
      for S in Lengths'Range loop
         if Lengths (S) /= 0 then
            Item.Symbol (Offsets (Lengths (S))) := S - Lengths'First;
            Offsets (Lengths (S)) := Offsets (Lengths (S)) + 1;
         end if;
      end loop;
      --  The short codes in the table, by their bits as the stream holds
      --  them: Deflate packs a code's first bit lowest.
      declare
         Value : Natural := 0;
      begin
         for Len in 1 .. Fast_Bits loop
            for Index in 0 .. Item.Count (Len) - 1 loop
               declare
                  Reversed : Natural := 0;
                  Bits     : Natural := Value;
               begin
                  for Ignored in 1 .. Len loop
                     Reversed := Reversed * 2 + Bits mod 2;
                     Bits := Bits / 2;
                  end loop;
                  for Fill in 0 .. 2 ** (Fast_Bits - Len) - 1 loop
                     Item.Fast (Reversed + Fill * 2 ** Len) :=
                       Unsigned_16 (Len * 512 + Item.Symbol (Next + Index));
                  end loop;
               end;
               Value := Value + 1;
            end loop;
            Next := Next + Item.Count (Len);
            Value := Value * 2;
         end loop;
      end;
   end Build;

   Length_Base  : constant array (257 .. 285) of Natural :=
     [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
      35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
   Length_Extra : constant array (257 .. 285) of Natural :=
     [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
      3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
   Distance_Base  : constant array (0 .. 29) of Natural :=
     [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
      257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
      8193, 12289, 16385, 24577];
   Distance_Extra : constant array (0 .. 29) of Natural :=
     [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
      7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
   Length_Order : constant array (0 .. 18) of Natural :=
     [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

   type Byte_Access is access Zlib.Byte_Array;
   procedure Free is new Ada.Unchecked_Deallocation (Zlib.Byte_Array, Byte_Access);

   --  The fixed codes, built as the package is elaborated: built on first
   --  use, two tasks inflating at once could read one half made.
   Fixed_Literal   : Code;
   Fixed_Distance  : Code;

   function Decode_Zlib (Input : Zlib.Byte_Array; Done : out Boolean) return Zlib.Byte_Array is
      Pos   : Natural := Input'First;
      Buf   : Unsigned_64 := 0;
      Count : Natural := 0;

      Output : Byte_Access := null;
      Last   : Integer := -1;

      procedure Refill is
      begin
         while Count <= 56 and then Pos <= Input'Last loop
            Buf := Buf or Shift_Left (Unsigned_64 (Input (Pos)), Count);
            Pos := Pos + 1;
            Count := Count + 8;
         end loop;
      end Refill;

      function Bits (N : Natural) return Natural is
         Value : Natural;
      begin
         if N = 0 then
            return 0;
         end if;
         if Count < N then
            Refill;
            if Count < N then
               raise Declined;
            end if;
         end if;
         Value := Natural (Buf and Shift_Left (1, N) - 1);
         Buf := Shift_Right (Buf, N);
         Count := Count - N;
         return Value;
      end Bits;

      function Decode (Item : Code) return Natural is
         Entry_Of : Unsigned_16;
      begin
         if Count < 15 then
            Refill;
         end if;
         Entry_Of := Item.Fast (Natural (Buf and (2 ** Fast_Bits - 1)));
         if Entry_Of /= 0 then
            declare
               Len : constant Natural := Natural (Entry_Of / 512);
            begin
               if Len > Count then
                  raise Declined;
               end if;
               Buf := Shift_Right (Buf, Len);
               Count := Count - Len;
               return Natural (Entry_Of mod 512);
            end;
         end if;
         --  Longer than the table: one bit at a time, as the code's
         --  canonical order gives it.
         declare
            Code_Value : Natural := 0;
            First      : Natural := 0;
            Index      : Natural := 0;
         begin
            for Len in 1 .. 15 loop
               exit when Len > Count;
               Code_Value := Code_Value
                 + Natural (Shift_Right (Buf, Len - 1) and 1);
               if Code_Value < First + Item.Count (Len) then
                  Buf := Shift_Right (Buf, Len);
                  Count := Count - Len;
                  return Item.Symbol (Index + (Code_Value - First));
               end if;
               Index := Index + Item.Count (Len);
               First := (First + Item.Count (Len)) * 2;
               Code_Value := Code_Value * 2;
            end loop;
            raise Declined;
         end;
      end Decode;

      --  Room for N more bytes.
      procedure Reserve (N : Natural) is
      begin
         if Last + N > Output'Last then
            declare
               Grown : constant Byte_Access :=
                 new Zlib.Byte_Array (0 .. Natural'Max (2 * Output'Length, Last + N + 1) - 1);
            begin
               Grown (0 .. Last) := Output (0 .. Last);
               Free (Output);
               Output := Grown;
            end;
         end if;
      end Reserve;

      procedure Inflate_Block (Literal, Distance : Code) is
      begin
         loop
            declare
               Symbol : constant Natural := Decode (Literal);
            begin
               if Symbol < 256 then
                  Reserve (1);
                  Last := Last + 1;
                  Output (Last) := Zlib.Byte (Symbol);
               elsif Symbol = 256 then
                  return;
               elsif Symbol > 285 then
                  raise Declined;
               else
                  declare
                     Len  : constant Natural := Length_Base (Symbol) + Bits (Length_Extra (Symbol));
                     Dsym : constant Natural := Decode (Distance);
                  begin
                     if Dsym > 29 then
                        raise Declined;
                     end if;
                     declare
                        Dist : constant Natural := Distance_Base (Dsym) + Bits (Distance_Extra (Dsym));
                     begin
                        if Dist > Last + 1 then
                           raise Declined;
                        end if;
                        Reserve (Len);
                        if Dist >= Len then
                           Output (Last + 1 .. Last + Len) := Output (Last + 1 - Dist .. Last + Len - Dist);
                        else
                           for K in Last + 1 .. Last + Len loop
                              Output (K) := Output (K - Dist);
                           end loop;
                        end if;
                        Last := Last + Len;
                     end;
                  end;
               end if;
            end;
         end loop;
      end Inflate_Block;

      procedure Dynamic_Block is
         HLIT    : constant Natural := Bits (5) + 257;
         HDIST   : constant Natural := Bits (5) + 1;
         HCLEN   : constant Natural := Bits (4) + 4;
         Lengths : Length_Array (0 .. 18) := [others => 0];
         Lencode : Code;
         All_Lengths : Length_Array (0 .. HLIT + HDIST - 1) := [others => 0];
         Index   : Natural := 0;
         Literal, Distance : Code;
      begin
         if HLIT > 286 or else HDIST > 30 then
            raise Declined;
         end if;
         for K in 0 .. HCLEN - 1 loop
            Lengths (Length_Order (K)) := Bits (3);
         end loop;
         Build (Lencode, Lengths);
         while Index < HLIT + HDIST loop
            declare
               Symbol : constant Natural := Decode (Lencode);
               Repeat : Natural;
               Value  : Natural := 0;
            begin
               if Symbol < 16 then
                  All_Lengths (Index) := Symbol;
                  Index := Index + 1;
               else
                  if Symbol = 16 then
                     if Index = 0 then
                        raise Declined;
                     end if;
                     Value := All_Lengths (Index - 1);
                     Repeat := 3 + Bits (2);
                  elsif Symbol = 17 then
                     Repeat := 3 + Bits (3);
                  else
                     Repeat := 11 + Bits (7);
                  end if;
                  if Index + Repeat > HLIT + HDIST then
                     raise Declined;
                  end if;
                  All_Lengths (Index .. Index + Repeat - 1) := [others => Value];
                  Index := Index + Repeat;
               end if;
            end;
         end loop;
         --  A block with no end-of-block code could never end.
         if All_Lengths (256) = 0 then
            raise Declined;
         end if;
         Build (Literal, All_Lengths (0 .. HLIT - 1));
         Build (Distance, All_Lengths (HLIT .. HLIT + HDIST - 1));
         Inflate_Block (Literal, Distance);
      end Dynamic_Block;

      Final : Boolean := False;
   begin
      Done := False;
      --  The zlib header: Deflate, a window zlib knows, the check holding,
      --  and no preset dictionary.
      if Input'Length < 6 then
         return [1 .. 0 => 0];
      end if;
      declare
         CMF : constant Natural := Natural (Input (Input'First));
         FLG : constant Natural := Natural (Input (Input'First + 1));
      begin
         if CMF mod 16 /= 8 or else CMF / 16 > 7 or else (CMF * 256 + FLG) mod 31 /= 0
           or else (FLG / 32) mod 2 = 1
         then
            return [1 .. 0 => 0];
         end if;
      end;
      Pos := Input'First + 2;
      --  Room for what such data usually inflates to.
      Output := new Zlib.Byte_Array (0 .. Natural'Max (4 * Input'Length, 4096) - 1);

      while not Final loop
         Final := Bits (1) = 1;
         case Bits (2) is
            when 0 =>
               --  Stored: from the next byte, as many as it says.
               declare
                  Dropped : constant Natural := Bits (Count mod 8);
                  Len     : constant Natural := Bits (16);
                  Nlen    : constant Natural := Bits (16);
                  pragma Unreferenced (Dropped);
               begin
                  if Len + Nlen /= 16#FFFF# then
                     raise Declined;
                  end if;
                  Reserve (Len);
                  for Ignored in 1 .. Len loop
                     if Count >= 8 then
                        Last := Last + 1;
                        Output (Last) := Zlib.Byte (Buf and 16#FF#);
                        Buf := Shift_Right (Buf, 8);
                        Count := Count - 8;
                     elsif Pos <= Input'Last then
                        Last := Last + 1;
                        Output (Last) := Input (Pos);
                        Pos := Pos + 1;
                     else
                        raise Declined;
                     end if;
                  end loop;
               end;
            when 1 =>
               Inflate_Block (Fixed_Literal, Fixed_Distance);
            when 2 =>
               Dynamic_Block;
            when others =>
               raise Declined;
         end case;
      end loop;

      --  The Adler-32 of what came out, from the next byte; and nothing
      --  after it.
      declare
         Dropped  : constant Natural := Bits (Count mod 8);
         --  Big-endian, one byte after another: each read a statement of
         --  its own, the order of operands being the compiler's.
         B1       : constant Unsigned_32 := Unsigned_32 (Bits (8));
         B2       : constant Unsigned_32 := Unsigned_32 (Bits (8));
         B3       : constant Unsigned_32 := Unsigned_32 (Bits (8));
         B4       : constant Unsigned_32 := Unsigned_32 (Bits (8));
         Expected : constant Unsigned_32 :=
           Shift_Left (B1, 24) or Shift_Left (B2, 16) or Shift_Left (B3, 8) or B4;
         A        : Unsigned_32 := 1;
         B        : Unsigned_32 := 0;
         Next     : Integer := 0;
         pragma Unreferenced (Dropped);
      begin
         if Count /= 0 or else Pos <= Input'Last then
            raise Declined;
         end if;
         while Next <= Last loop
            declare
               Stop : constant Integer := Integer'Min (Last, Next + 5551);
            begin
               for K in Next .. Stop loop
                  A := A + Unsigned_32 (Output (K));
                  B := B + A;
               end loop;
               A := A mod 65521;
               B := B mod 65521;
               Next := Stop + 1;
            end;
         end loop;
         if (Shift_Left (B, 16) or A) /= Expected then
            raise Declined;
         end if;
      end;

      declare
         --  Numbered from one, as the streaming decoder numbers its own.
         Result : constant Zlib.Byte_Array (1 .. Last + 1) := Output (0 .. Last);
      begin
         Free (Output);
         Done := True;
         return Result;
      end;
   exception
      when Declined | Constraint_Error | Storage_Error =>
         Free (Output);
         Done := False;
         return [1 .. 0 => 0];
   end Decode_Zlib;

begin
   declare
      Lengths : Length_Array (0 .. 287);
   begin
      Lengths (0 .. 143) := [others => 8];
      Lengths (144 .. 255) := [others => 9];
      Lengths (256 .. 279) := [others => 7];
      Lengths (280 .. 287) := [others => 8];
      Build (Fixed_Literal, Lengths);
      Build (Fixed_Distance, Length_Array'(0 .. 29 => 5));
   end;
end Zlib.Fast_Inflate;
