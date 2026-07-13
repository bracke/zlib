package body Zlib.BZip2_Bits is

   use type Interfaces.Unsigned_32;

   procedure Reset (R : out Reader; First : Natural) is
   begin
      R := (Next_Byte => First, Bit_Index => 0);
   end Reset;

   function Read_Bit
     (R      : in out Reader;
      Data   : Byte_Array;
      Status : out Status_Code) return Boolean
   is
      Current : Byte;
      Mask    : Byte;
   begin
      Status := Ok;

      if R.Next_Byte > Data'Last then
         Status := Unexpected_End_Of_Input;
         return False;
      end if;

      Current := Data (R.Next_Byte);
      Mask := Byte (2 ** (7 - R.Bit_Index));

      if R.Bit_Index = 7 then
         R.Bit_Index := 0;
         R.Next_Byte := R.Next_Byte + 1;
      else
         R.Bit_Index := R.Bit_Index + 1;
      end if;

      return (Current and Mask) /= 0;
   end Read_Bit;

   function Read_Bits
     (R      : in out Reader;
      Data   : Byte_Array;
      Count  : Natural;
      Status : out Status_Code) return Interfaces.Unsigned_32
   is
      Result : Interfaces.Unsigned_32 := 0;
      Bit    : Boolean;
   begin
      Status := Ok;

      for Unused_Index in 1 .. Count loop
         Bit := Read_Bit (R, Data, Status);
         if Status /= Ok then
            return 0;
         end if;
         Result := Interfaces.Shift_Left (Result, 1);
         if Bit then
            Result := Result or 1;
         end if;
      end loop;

      return Result;
   end Read_Bits;

   procedure Align_To_Byte (R : in out Reader) is
   begin
      if R.Bit_Index /= 0 then
         R.Bit_Index := 0;
         R.Next_Byte := R.Next_Byte + 1;
      end if;
   end Align_To_Byte;

   function Byte_Position (R : Reader) return Natural is
   begin
      return R.Next_Byte;
   end Byte_Position;

   function Is_Byte_Aligned (R : Reader) return Boolean is
   begin
      return R.Bit_Index = 0;
   end Is_Byte_Aligned;

end Zlib.BZip2_Bits;
