package body Zlib.Zstd_Bits is

   use type Interfaces.Unsigned_32;

   function Bit_At (Data : Byte_Array; Index : Natural) return Boolean;
   --  Bit Index of the backward view: byte order reversed, MSB first in a byte.

   function Bit_At (Data : Byte_Array; Index : Natural) return Boolean is
      Item : constant Byte := Data (Data'Last - Index / 8);
      Mask : constant Byte := Byte (2 ** (7 - Index mod 8));
   begin
      return (Item and Mask) /= 0;
   end Bit_At;

   ----------------------------------------------------------------------------
   --  Forward, LSB-first
   ----------------------------------------------------------------------------

   procedure Reset (R : out Forward_Reader; First : Natural) is
   begin
      R := (Next_Byte => First, Bit_Index => 0);
   end Reset;

   function Read
     (R      : in out Forward_Reader;
      Data   : Byte_Array;
      Count  : Natural;
      Status : out Status_Code) return Interfaces.Unsigned_32
   is
      Result : Interfaces.Unsigned_32 := 0;
   begin
      Status := Ok;

      for Index in 0 .. Count - 1 loop
         if R.Next_Byte > Data'Last then
            Status := Unexpected_End_Of_Input;
            return 0;
         end if;

         if (Data (R.Next_Byte) and Byte (2 ** R.Bit_Index)) /= 0 then
            Result := Result or Interfaces.Shift_Left (1, Index);
         end if;

         if R.Bit_Index = 7 then
            R.Bit_Index := 0;
            R.Next_Byte := R.Next_Byte + 1;
         else
            R.Bit_Index := R.Bit_Index + 1;
         end if;
      end loop;

      return Result;
   end Read;

   function Peek
     (R      : Forward_Reader;
      Data   : Byte_Array;
      Count  : Natural) return Interfaces.Unsigned_32
   is
      Result : Interfaces.Unsigned_32 := 0;
      Scan   : Forward_Reader := R;
   begin
      for Index in 0 .. Count - 1 loop
         --  Past the end reads as zero: the table description's final symbol may
         --  need bits the encoder never had to write.
         if Scan.Next_Byte <= Data'Last
           and then (Data (Scan.Next_Byte) and Byte (2 ** Scan.Bit_Index)) /= 0
         then
            Result := Result or Interfaces.Shift_Left (1, Index);
         end if;

         if Scan.Bit_Index = 7 then
            Scan.Bit_Index := 0;
            Scan.Next_Byte := Scan.Next_Byte + 1;
         else
            Scan.Bit_Index := Scan.Bit_Index + 1;
         end if;
      end loop;

      return Result;
   end Peek;

   procedure Skip (R : in out Forward_Reader; Count : Natural) is
      Total : constant Natural := R.Bit_Index + Count;
   begin
      R.Next_Byte := R.Next_Byte + Total / 8;
      R.Bit_Index := Total mod 8;
   end Skip;

   function Bytes_Used (R : Forward_Reader; First : Natural) return Natural is
   begin
      return (R.Next_Byte - First) + (if R.Bit_Index > 0 then 1 else 0);
   end Bytes_Used;

   ----------------------------------------------------------------------------
   --  Backward, MSB-first
   ----------------------------------------------------------------------------

   procedure Start
     (R      : out Backward_Reader;
      Data   : Byte_Array;
      Status : out Status_Code)
   is
      Padding : Natural := 0;
   begin
      R := (Position => 0, Total => 0);
      Status := Ok;

      if Data'Length = 0 then
         Status := Unexpected_End_Of_Input;
         return;
      end if;

      if Data (Data'Last) = 0 then
         --  No end mark: the stream's length is not recoverable.
         Status := Invalid_Block_Type;
         return;
      end if;

      --  Discard the zero padding above the end mark, then the mark itself.
      while not Bit_At (Data, Padding) loop
         Padding := Padding + 1;
      end loop;

      R.Total := Data'Length * 8;
      R.Position := Padding + 1;
   end Start;

   function Read
     (R      : in out Backward_Reader;
      Data   : Byte_Array;
      Count  : Natural;
      Status : out Status_Code) return Interfaces.Unsigned_32
   is
      Result : Interfaces.Unsigned_32 := 0;
   begin
      Status := Ok;

      for Unused_Index in 1 .. Count loop
         if R.Position >= R.Total then
            Status := Unexpected_End_Of_Input;
            return 0;
         end if;

         Result := Interfaces.Shift_Left (Result, 1);
         if Bit_At (Data, R.Position) then
            Result := Result or 1;
         end if;
         R.Position := R.Position + 1;
      end loop;

      return Result;
   end Read;

   function Peek
     (R     : Backward_Reader;
      Data  : Byte_Array;
      Count : Natural) return Interfaces.Unsigned_32
   is
      Result : Interfaces.Unsigned_32 := 0;
      Cursor : Natural := R.Position;
   begin
      for Unused_Index in 1 .. Count loop
         Result := Interfaces.Shift_Left (Result, 1);
         if Cursor < R.Total and then Bit_At (Data, Cursor) then
            Result := Result or 1;
         end if;
         Cursor := Cursor + 1;
      end loop;

      return Result;
   end Peek;

   procedure Skip
     (R      : in out Backward_Reader;
      Count  : Natural;
      Status : out Status_Code) is
   begin
      Status := Ok;

      if R.Position + Count > R.Total then
         Status := Unexpected_End_Of_Input;
         return;
      end if;

      R.Position := R.Position + Count;
   end Skip;

   function Exhausted (R : Backward_Reader) return Boolean is
   begin
      return R.Position >= R.Total;
   end Exhausted;

   ----------------------------------------------------------------------------
   --  Backward writer
   ----------------------------------------------------------------------------

   procedure Reset (W : out Backward_Writer) is
   begin
      W.Fields.Clear;
      W.Length := 0;
   end Reset;

   procedure Write
     (W     : in out Backward_Writer;
      Value : Interfaces.Unsigned_32;
      Count : Natural) is
   begin
      if Count = 0 then
         return;
      end if;

      W.Fields.Append (Field'(Value => Value, Count => Count));
      W.Length := W.Length + Count;
   end Write;

   function Finish (W : Backward_Writer) return Byte_Array is
      Payload : constant Natural := W.Length;
      --  The end mark takes one bit, and the whole must fill whole bytes.
      Total   : constant Natural := ((Payload + 1) + 7) / 8 * 8;
      Length  : constant Natural := Total / 8;
      Padding : constant Natural := Total - Payload - 1;

      Result : Byte_Array (1 .. Length) := [others => 0];
      Cursor : Natural := Padding + 1;

      procedure Put (Index : Natural; Bit : Boolean);

      procedure Put (Index : Natural; Bit : Boolean) is
         Position : constant Natural := Result'Last - Index / 8;
         Mask     : constant Byte := Byte (2 ** (7 - Index mod 8));
      begin
         if Bit then
            Result (Position) := Result (Position) or Mask;
         end if;
      end Put;

   begin
      --  The end mark sits above the payload; everything above it is padding.
      Put (Padding, True);

      --  Fields come out back to front, each field's own bits most significant
      --  first, so the reader returns them in the order the encoder needs.
      for Index in reverse 0 .. Natural (W.Fields.Length) - 1 loop
         declare
            Item : constant Field := W.Fields (Index);
         begin
            for Bit in reverse 0 .. Item.Count - 1 loop
               Put
                 (Cursor,
                  (Interfaces.Shift_Right (Item.Value, Bit) and 1) /= 0);
               Cursor := Cursor + 1;
            end loop;
         end;
      end loop;

      return Result;
   end Finish;

end Zlib.Zstd_Bits;
