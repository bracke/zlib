with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;
with Zlib.Fuzzing;

procedure fuzz_lifecycle is
   use type Interfaces.Unsigned_32;

   function Arg_Natural
     (Index   : Positive;
      Default : Natural)
      return Natural is
   begin
      if Ada.Command_Line.Argument_Count >= Index then
         return Natural'Value (Ada.Command_Line.Argument (Index));
      end if;
      return Default;
   exception
      when Constraint_Error =>
         return Default;
   end Arg_Natural;

   function Arg_Seed
     (Index   : Positive;
      Default : Interfaces.Unsigned_32)
      return Interfaces.Unsigned_32 is
   begin
      if Ada.Command_Line.Argument_Count >= Index then
         return Interfaces.Unsigned_32'Value (Ada.Command_Line.Argument (Index));
      end if;
      return Default;
   exception
      when Constraint_Error =>
         return Default;
   end Arg_Seed;

   Target     : constant Zlib.Fuzzing.Target_Kind := Zlib.Fuzzing.Lifecycle_Target;
   Iterations : constant Natural := Arg_Natural (1, 200);
   Seed       : constant Interfaces.Unsigned_32 := Arg_Seed (2, 63);
   Result     : constant Zlib.Fuzzing.Fuzz_Result :=
     Zlib.Fuzzing.Run (Target, Seed, Iterations);
begin
   Ada.Text_IO.Put_Line
     ("target=Lifecycle_Target seed=" & Interfaces.Unsigned_32'Image (Seed) &
      " iterations=" & Natural'Image (Iterations) &
      " runs=" & Natural'Image (Result.Runs) &
      " ok=" & Natural'Image (Result.Success) &
      " deterministic_failures=" & Natural'Image (Result.Failures) &
      " crashes=" & Natural'Image (Result.Crashes) &
      " digest=" & Interfaces.Unsigned_32'Image (Result.Digest) &
      " last_input_len=" & Natural'Image (Result.Last_Input_Length) &
      " last_input_hex=" & Zlib.Fuzzing.Last_Hex_Snippet (Result));

   if not Zlib.Fuzzing.Acceptable (Target, Result) then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end fuzz_lifecycle;
