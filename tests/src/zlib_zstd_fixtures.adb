with Interfaces;

package body Zlib_Zstd_Fixtures is

   use type Interfaces.Unsigned_32;

   function Noise_Plain return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (0 .. 2_999);
      State  : Interfaces.Unsigned_32 := 12_345;
   begin
      for Index in Result'Range loop
         State := 1_103_515_245 * State + 12_345;
         Result (Index) :=
           Zlib.Byte (Interfaces.Shift_Right (State, 8) mod 251);
      end loop;
      return Result;
   end Noise_Plain;

   function Pattern_Plain (Length : Natural) return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (0 .. Length - 1);
   begin
      for Index in Result'Range loop
         Result (Index) := Zlib.Byte ((Index mod 61) + 32);
      end loop;
      return Result;
   end Pattern_Plain;

end Zlib_Zstd_Fixtures;
