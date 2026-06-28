package body Zlib.Checksums is
   use type Interfaces.Unsigned_32;

   Mod_Adler : constant Interfaces.Unsigned_32 := 65_521;

   procedure Reset
     (State : out Adler32_State)
   is
   begin
      State.A := 1;
      State.B := 0;
   end Reset;

   procedure Update
     (State : in out Adler32_State;
      B     : Zlib.Byte)
   is
   begin
      State.A := (State.A + Interfaces.Unsigned_32 (B)) mod Mod_Adler;
      State.B := (State.B + State.A) mod Mod_Adler;
   end Update;

   procedure Update
     (State : in out Adler32_State;
      B     : Ada.Streams.Stream_Element)
   is
   begin
      Update (State, Zlib.Byte (B));
   end Update;

   function Value
     (State : Adler32_State)
      return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Shift_Left (State.B, 16) or State.A;
   end Value;

   function Adler32
     (Data : Zlib.Byte_Array)
      return Interfaces.Unsigned_32
   is
      State : Adler32_State;
   begin
      Reset (State);

      for I in Data'Range loop
         Update (State, Data (I));
      end loop;

      return Value (State);
   end Adler32;

end Zlib.Checksums;
