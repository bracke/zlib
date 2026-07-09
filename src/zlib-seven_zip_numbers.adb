package body Zlib.Seven_Zip_Numbers is

   use type Interfaces.Unsigned_64;
   use type Interfaces.Unsigned_32;

   function Encoded_Length
     (Value : Interfaces.Unsigned_64)
      return Encoded_Number_Length
     with SPARK_Mode => On
   is
   begin
      if Value < 2 ** 7 then
         return 1;
      elsif Value < 2 ** 14 then
         return 2;
      elsif Value < 2 ** 21 then
         return 3;
      elsif Value < 2 ** 28 then
         return 4;
      elsif Value < 2 ** 35 then
         return 5;
      elsif Value < 2 ** 42 then
         return 6;
      elsif Value < 2 ** 49 then
         return 7;
      elsif Value < 2 ** 56 then
         return 8;
      else
         return 9;
      end if;
   end Encoded_Length;

   function Encode_Number
     (Value : Interfaces.Unsigned_64)
      return Byte_Array
     with SPARK_Mode => Off
   is
      Length : constant Encoded_Number_Length := Encoded_Length (Value);
      Result : Byte_Array (1 .. Length) := [others => 0];
   begin
      if Length = 1 then
         Result (1) := Byte (Value);
      elsif Length = 9 then
         declare
            Current : Interfaces.Unsigned_64 := Value;
         begin
            Result (1) := 16#FF#;

            for I in 2 .. 9 loop
               Result (I) := Byte (Current and 16#FF#);
               Current := Interfaces.Shift_Right (Current, 8);
            end loop;
         end;
      else
         declare
            Extra_Bytes : constant Natural := Length - 1;
            Prefix      : constant Natural := 256 - 2 ** (8 - Extra_Bytes);
            High        : constant Natural :=
              Natural
                (Interfaces.Shift_Right (Value, 8 * Extra_Bytes)
                 and Interfaces.Unsigned_64 (16#FF# / 2 ** Extra_Bytes));
            Current     : Interfaces.Unsigned_64 := Value;
         begin
            Result (1) := Byte (Prefix + High);

            for I in 2 .. Length loop
               Result (I) := Byte (Current and 16#FF#);
               Current := Interfaces.Shift_Right (Current, 8);
            end loop;
         end;
      end if;

      return Result;
   end Encode_Number;

   function U32_At
     (Data : Byte_Array;
      Pos  : Natural)
      return Interfaces.Unsigned_32
     with SPARK_Mode => On
   is
   begin
      return Interfaces.Unsigned_32 (Data (Pos))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 1)), 8)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 2)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 3)), 24);
   end U32_At;

   function U64_At
     (Data : Byte_Array;
      Pos  : Natural)
      return Interfaces.Unsigned_64
     with SPARK_Mode => On
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for I in 0 .. 7 loop
         Result :=
           Result
           or Interfaces.Shift_Left
             (Interfaces.Unsigned_64 (Data (Pos + I)), 8 * I);
      end loop;

      return Result;
   end U64_At;

   function Read_Number
     (Data  : Byte_Array;
      Pos   : in out Natural;
      Last  : Natural;
      Value : out Interfaces.Unsigned_64) return Boolean
     with SPARK_Mode => Off
   is
      First : Natural;
      Extra : Natural := 0;
      Mask  : Natural := 16#80#;
   begin
      Value := 0;
      if Pos > Last then
         return False;
      end if;

      First := Natural (Data (Pos));
      Pos := Pos + 1;

      while Extra < 8 and then (First / Mask) mod 2 = 1 loop
         Extra := Extra + 1;
         Mask := Mask / 2;
      end loop;

      if Extra = 0 then
         Value := Interfaces.Unsigned_64 (First);
         return True;
      end if;

      if Pos > Last or else Last - Pos + 1 < Extra then
         return False;
      end if;

      if Extra = 8 then
         for I in 0 .. 7 loop
            Value :=
              Value
              or Interfaces.Shift_Left
                (Interfaces.Unsigned_64 (Data (Pos + I)), 8 * I);
         end loop;
         Pos := Pos + 8;
      else
         Value :=
           Interfaces.Shift_Left
             (Interfaces.Unsigned_64 (First mod Mask), 8 * Extra);
         for I in 0 .. Extra - 1 loop
            Value :=
              Value
              or Interfaces.Shift_Left
                (Interfaces.Unsigned_64 (Data (Pos + I)), 8 * I);
         end loop;
         Pos := Pos + Extra;
      end if;

      return True;
   exception
      when others =>
         Value := 0;
         return False;
   end Read_Number;

end Zlib.Seven_Zip_Numbers;
