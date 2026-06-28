package body Zlib.Bits is

   procedure Init
     (R    : out Bit_Reader;
      Data : Zlib.Byte_Array)
   is
   begin
      R.Data.Clear;

      for I in Data'Range loop
         R.Data.Append (Data (I));
      end loop;

      R.Byte_Index := 0;
      R.Bit_Index  := 0;
   end Init;

   function Read_Bit
     (R      : in out Bit_Reader;
      Status : out Zlib.Status_Code)
      return Boolean
   is
      Current : Zlib.Byte;
      Mask    : Zlib.Byte;
      Result  : Boolean;
   begin
      if R.Byte_Index >= Natural (R.Data.Length) then
         Status := Zlib.Unexpected_End_Of_Input;
         return False;
      end if;

      Current := R.Data.Element (R.Byte_Index);
      Mask    := Zlib.Byte (2 ** R.Bit_Index);
      Result  := (Current and Mask) /= 0;

      if R.Bit_Index = 7 then
         R.Bit_Index  := 0;
         R.Byte_Index := R.Byte_Index + 1;
      else
         R.Bit_Index := R.Bit_Index + 1;
      end if;

      Status := Zlib.Ok;
      return Result;
   end Read_Bit;

   function Read_Bits
     (R      : in out Bit_Reader;
      Count  : Natural;
      Status : out Zlib.Status_Code)
      return Natural
   is
      Result : Natural := 0;
      Bit    : Boolean;
   begin
      if Count = 0 then
         Status := Zlib.Ok;
         return 0;
      end if;

      for I in 0 .. Count - 1 loop
         Bit := Read_Bit (R, Status);

         if Status /= Zlib.Ok then
            return 0;
         end if;

         if Bit then
            Result := Result + 2 ** I;
         end if;
      end loop;

      Status := Zlib.Ok;
      return Result;
   end Read_Bits;

   procedure Align_To_Byte
     (R : in out Bit_Reader)
   is
   begin
      if R.Bit_Index /= 0 then
         R.Bit_Index  := 0;
         R.Byte_Index := R.Byte_Index + 1;
      end if;
   end Align_To_Byte;

   function Read_Byte_Aligned
     (R      : in out Bit_Reader;
      Status : out Zlib.Status_Code)
      return Zlib.Byte
   is
      Result : Zlib.Byte;
   begin
      if R.Bit_Index /= 0 then
         Status := Zlib.Invalid_Stored_Block;
         return 0;
      end if;

      if R.Byte_Index >= Natural (R.Data.Length) then
         Status := Zlib.Unexpected_End_Of_Input;
         return 0;
      end if;

      Result := R.Data.Element (R.Byte_Index);
      R.Byte_Index := R.Byte_Index + 1;

      Status := Zlib.Ok;
      return Result;
   end Read_Byte_Aligned;

end Zlib.Bits;
