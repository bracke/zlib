package body Zlib.Zstd_XXH64 is

   use type Interfaces.Unsigned_64;

   Prime_1 : constant Interfaces.Unsigned_64 := 11_400_714_785_074_694_791;
   Prime_2 : constant Interfaces.Unsigned_64 := 14_029_467_366_897_019_727;
   Prime_3 : constant Interfaces.Unsigned_64 := 1_609_587_929_392_839_161;
   Prime_4 : constant Interfaces.Unsigned_64 := 9_650_029_242_287_828_579;
   Prime_5 : constant Interfaces.Unsigned_64 := 2_870_177_450_012_600_261;

   function Read_64
     (Data : Byte_Array; At_Index : Natural) return Interfaces.Unsigned_64;
   function Read_32
     (Data : Byte_Array; At_Index : Natural) return Interfaces.Unsigned_64;
   function Round
     (Accumulator : Interfaces.Unsigned_64;
      Input       : Interfaces.Unsigned_64) return Interfaces.Unsigned_64;
   function Merge_Round
     (Accumulator : Interfaces.Unsigned_64;
      Value       : Interfaces.Unsigned_64) return Interfaces.Unsigned_64;

   function Read_64
     (Data : Byte_Array; At_Index : Natural) return Interfaces.Unsigned_64
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for Offset in reverse 0 .. 7 loop
         Result :=
           Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_64 (Data (At_Index + Offset));
      end loop;
      return Result;
   end Read_64;

   function Read_32
     (Data : Byte_Array; At_Index : Natural) return Interfaces.Unsigned_64
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for Offset in reverse 0 .. 3 loop
         Result :=
           Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_64 (Data (At_Index + Offset));
      end loop;
      return Result;
   end Read_32;

   function Round
     (Accumulator : Interfaces.Unsigned_64;
      Input       : Interfaces.Unsigned_64) return Interfaces.Unsigned_64
   is
      Value : Interfaces.Unsigned_64 := Accumulator;
   begin
      Value := Value + Input * Prime_2;
      Value := Interfaces.Rotate_Left (Value, 31);
      return Value * Prime_1;
   end Round;

   function Merge_Round
     (Accumulator : Interfaces.Unsigned_64;
      Value       : Interfaces.Unsigned_64) return Interfaces.Unsigned_64
   is
      Folded : constant Interfaces.Unsigned_64 := Round (0, Value);
   begin
      return (Accumulator xor Folded) * Prime_1 + Prime_4;
   end Merge_Round;

   function Compute
     (Data : Byte_Array;
      Seed : Interfaces.Unsigned_64 := 0) return Interfaces.Unsigned_64
   is
      Length    : constant Natural := Data'Length;
      Position  : Natural := Data'First;
      Remaining : Natural := Length;
      Hash      : Interfaces.Unsigned_64;
   begin
      if Remaining >= 32 then
         declare
            V1 : Interfaces.Unsigned_64 := Seed + Prime_1 + Prime_2;
            V2 : Interfaces.Unsigned_64 := Seed + Prime_2;
            V3 : Interfaces.Unsigned_64 := Seed;
            V4 : Interfaces.Unsigned_64 := Seed - Prime_1;
         begin
            while Remaining >= 32 loop
               V1 := Round (V1, Read_64 (Data, Position));
               V2 := Round (V2, Read_64 (Data, Position + 8));
               V3 := Round (V3, Read_64 (Data, Position + 16));
               V4 := Round (V4, Read_64 (Data, Position + 24));
               Position := Position + 32;
               Remaining := Remaining - 32;
            end loop;

            Hash :=
              Interfaces.Rotate_Left (V1, 1)
              + Interfaces.Rotate_Left (V2, 7)
              + Interfaces.Rotate_Left (V3, 12)
              + Interfaces.Rotate_Left (V4, 18);

            Hash := Merge_Round (Hash, V1);
            Hash := Merge_Round (Hash, V2);
            Hash := Merge_Round (Hash, V3);
            Hash := Merge_Round (Hash, V4);
         end;
      else
         Hash := Seed + Prime_5;
      end if;

      Hash := Hash + Interfaces.Unsigned_64 (Length);

      while Remaining >= 8 loop
         Hash := Hash xor Round (0, Read_64 (Data, Position));
         Hash := Interfaces.Rotate_Left (Hash, 27) * Prime_1 + Prime_4;
         Position := Position + 8;
         Remaining := Remaining - 8;
      end loop;

      if Remaining >= 4 then
         Hash := Hash xor (Read_32 (Data, Position) * Prime_1);
         Hash := Interfaces.Rotate_Left (Hash, 23) * Prime_2 + Prime_3;
         Position := Position + 4;
         Remaining := Remaining - 4;
      end if;

      while Remaining > 0 loop
         Hash :=
           Hash xor (Interfaces.Unsigned_64 (Data (Position)) * Prime_5);
         Hash := Interfaces.Rotate_Left (Hash, 11) * Prime_1;
         Position := Position + 1;
         Remaining := Remaining - 1;
      end loop;

      Hash := Hash xor Interfaces.Shift_Right (Hash, 33);
      Hash := Hash * Prime_2;
      Hash := Hash xor Interfaces.Shift_Right (Hash, 29);
      Hash := Hash * Prime_3;
      Hash := Hash xor Interfaces.Shift_Right (Hash, 32);

      return Hash;
   end Compute;

end Zlib.Zstd_XXH64;
