with Interfaces;

package body Zlib_BZip2_Fixtures is

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

   function Multi_Plain return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (0 .. 249_999);
   begin
      for Index in Result'Range loop
         Result (Index) := Zlib.Byte ((Index mod 61) + 32);
      end loop;
      return Result;
   end Multi_Plain;

end Zlib_BZip2_Fixtures;
