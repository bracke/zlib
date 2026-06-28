package body Zlib.Huffman is

   function Reverse_Bits (Value : Natural; Length : Natural) return Natural is
      Result : Natural := 0;
      Temp   : Natural := Value;
   begin
      for I in 0 .. Length - 1 loop
         if Temp mod 2 = 1 then
            Result := Result + 2 ** (Length - 1 - I);
         end if;

         Temp := Temp / 2;
      end loop;

      return Result;
   end Reverse_Bits;

   procedure Clear (Table : out Decode_Table) is
   begin
      Table := (Lookup => [others => <>], Min_Length => 0, Max_Length => 0, Used_Count => 0);
   end Clear;

   procedure Fill_Lookup
     (Table  : in out Decode_Table;
      Code   : Natural;
      Length : Code_Length;
      Symbol : Symbol_Value;
      Status : out Zlib.Status_Code) is
   begin
      pragma Assert (Length > 0, "Huffman lookup length must be > 0");
      pragma Assert (Length <= 15, "Huffman lookup length must be <= 15");
      pragma Assert (Code < Table_Size, "Huffman lookup code out of range");

      if Table.Lookup (Code).Used then
         Status := Zlib.Invalid_Huffman_Code;
         return;
      end if;

      Table.Lookup (Code) :=
        (Used => True, Symbol => Symbol, Length => Length);

      if Table.Used_Count = 0 then
         Table.Min_Length := Length;
         Table.Max_Length := Length;
      else
         if Length < Table.Min_Length then
            Table.Min_Length := Length;
         end if;

         if Length > Table.Max_Length then
            Table.Max_Length := Length;
         end if;
      end if;

      Table.Used_Count := Table.Used_Count + 1;
      Status := Zlib.Ok;
   end Fill_Lookup;

   procedure Build
     (Lengths : Code_Length_Array;
      Table   : out Decode_Table;
      Status  : out Zlib.Status_Code)
   is
      Bl_Count  : array (Code_Length range 0 .. 15) of Natural :=
        [others => 0];
      Next_Code : array (Code_Length range 0 .. 15) of Natural :=
        [others => 0];
      Code      : Natural := 0;
      Len       : Code_Length;
      Rev_Code  : Natural;
   begin
      Clear (Table);

      for I in Lengths'Range loop
         if Lengths (I) /= 0 then
            Bl_Count (Lengths (I)) := Bl_Count (Lengths (I)) + 1;
         end if;
      end loop;

      declare
         Non_Zero_Count : Natural := 0;
      begin
         for Bits in 1 .. 15 loop
            Non_Zero_Count := Non_Zero_Count + Bl_Count (Bits);
         end loop;

         if Non_Zero_Count = 0 then
            Status := Zlib.Invalid_Huffman_Code;
            return;
         end if;
      end;

      declare
         Left : Integer := 1;
      begin
         for Bits in 1 .. 15 loop
            Left := Left * 2;
            Left := Left - Integer (Bl_Count (Bits));

            if Left < 0 then
               Status := Zlib.Invalid_Huffman_Code;
               return;
            end if;
         end loop;
      end;

      for Bits in 1 .. 15 loop
         Code := (Code + Bl_Count (Bits - 1)) * 2;
         Next_Code (Bits) := Code;
      end loop;

      for I in Lengths'Range loop
         Len := Lengths (I);

         if Len /= 0 then
            Rev_Code := Reverse_Bits (Next_Code (Len), Len);

            Fill_Lookup
              (Table  => Table,
               Code   => Rev_Code,
               Length => Len,
               Symbol => Symbol_Value (I - Lengths'First),
               Status => Status);

            if Status /= Zlib.Ok then
               return;
            end if;

            Next_Code (Len) := Next_Code (Len) + 1;
         end if;
      end loop;

      Status := Zlib.Ok;
   end Build;

   function Decode
     (R      : in out Zlib.Bits.Bit_Reader;
      Table  : Decode_Table;
      Status : out Zlib.Status_Code) return Symbol_Value
   is
      Code : Natural := 0;
      Bit  : Boolean;
      E    : Decode_E;
   begin
      if Table.Used_Count = 0 then
         Status := Zlib.Invalid_Huffman_Code;
         return 0;
      end if;

      for Len in 1 .. Table.Max_Length loop
         Bit := Zlib.Bits.Read_Bit (R, Status);

         if Status /= Zlib.Ok then
            return 0;
         end if;

         if Bit then
            Code := Code + 2 ** (Len - 1);
         end if;

         if Len >= Table.Min_Length then
            E := Table.Lookup (Code);
         else
            E := (Used => False, Symbol => 0, Length => 0);
         end if;

         if E.Used and then E.Length = Len then
            pragma Assert (E.Length = Len, "Huffman decode length mismatch");

            Status := Zlib.Ok;
            return E.Symbol;
         end if;
      end loop;

      Status := Zlib.Invalid_Huffman_Code;
      return 0;
   end Decode;

   function Decode_Streaming
     (Source      : in out Zlib.Stream_Bits.Bit_Source;
      Table       : Decode_Table;
      Code        : in out Natural;
      Length      : in out Code_Length;
      Read_Status : out Zlib.Stream_Bits.Read_Status;
      Status      : out Zlib.Status_Code) return Symbol_Value
   is
      Bit : Boolean;
      E   : Decode_E;
   begin
      if Table.Used_Count = 0 then
         Code := 0;
         Length := 0;
         Read_Status := Zlib.Stream_Bits.Ok;
         Status := Zlib.Invalid_Huffman_Code;
         return 0;
      end if;

      while Length < Table.Max_Length loop
         Bit := Zlib.Stream_Bits.Read_Bit (Source, Read_Status);

         case Read_Status is
            when Zlib.Stream_Bits.Ok =>
               null;
            when Zlib.Stream_Bits.Need_Input =>
               Status := Zlib.Ok;
               return 0;
            when Zlib.Stream_Bits.Invalid_State =>
               Code := 0;
               Length := 0;
               Status := Zlib.Invalid_Huffman_Code;
               return 0;
         end case;

         Length := Length + 1;

         if Bit then
            Code := Code + 2 ** (Length - 1);
         end if;

         if Length >= Table.Min_Length then
            E := Table.Lookup (Code);
         else
            E := (Used => False, Symbol => 0, Length => 0);
         end if;

         if E.Used and then E.Length = Length then
            Code := 0;
            Length := 0;
            Status := Zlib.Ok;
            return E.Symbol;
         end if;
      end loop;

      Code := 0;
      Length := 0;
      Read_Status := Zlib.Stream_Bits.Ok;
      Status := Zlib.Invalid_Huffman_Code;
      return 0;
   end Decode_Streaming;

end Zlib.Huffman;
