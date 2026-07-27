with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib; use Zlib;

package body Zlib_Insufficient_Memory_Tests is

   --  A decoded payload that cannot fit in the caller's stack must be reported
   --  as Insufficient_Memory. It must never be reported as
   --  Unexpected_End_Of_Input, which would blame well-formed input, nor escape
   --  as an exception from an API documented to return a status code.
   --
   --  The bound is made deterministic by running the call in a task with a
   --  small Storage_Size rather than depending on the machine's stack limit.

   Payload_Size : constant := 2 * 1024 * 1024;
   Runner_Stack : constant := 128 * 1024;

   type Byte_Array_Access is access Zlib.Byte_Array;

   procedure Free is new Ada.Unchecked_Deallocation
     (Zlib.Byte_Array, Byte_Array_Access);

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib insufficient-memory reporting");
   end Name;

   function Compressed_Payload return Zlib.Byte_Array is
      --  Built on the heap so that preparing the fixture does not itself
      --  depend on a large stack.
      Raw    : Byte_Array_Access := new Zlib.Byte_Array (1 .. Payload_Size);
      Status : Zlib.Status_Code := Zlib.Ok;
   begin
      Raw.all := [others => 65];

      declare
         Encoded : constant Zlib.Byte_Array :=
           Zlib.Deflate (Raw.all, Status => Status);
      begin
         Free (Raw);
         Assert (Status = Zlib.Ok, "fixture: Deflate must succeed");
         return Encoded;
      end;
   end Compressed_Payload;

   procedure Test_Inflate_Reports_Insufficient_Memory
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Encoded : constant Zlib.Byte_Array := Compressed_Payload;
      Outcome : Zlib.Status_Code := Zlib.Ok;
      Escaped : Boolean := False;
   begin
      declare
         task Runner with Storage_Size => Runner_Stack;

         task body Runner is
         begin
            declare
               Decoded : constant Zlib.Byte_Array :=
                 Zlib.Inflate (Encoded, Outcome);
            begin
               --  A run with enough room decodes the whole payload; a run
               --  without it must still leave a deterministic status.
               if Decoded'Length not in 0 | Payload_Size then
                  Escaped := True;
               end if;
            end;
         exception
            when others =>
               Escaped := True;
         end Runner;
      begin
         null;
      end;

      Assert
        (not Escaped,
         "Inflate must not raise out of a status-returning API");
      Assert
        (Outcome /= Zlib.Unexpected_End_Of_Input,
         "a well-formed stream must not be reported as truncated when memory "
         & "runs out");
      Assert
        (Outcome = Zlib.Insufficient_Memory,
         "expected Insufficient_Memory, got " & Zlib.Status_Image (Outcome));
   end Test_Inflate_Reports_Insufficient_Memory;

   overriding procedure Register_Tests
     (T : in out Test_Case) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Inflate_Reports_Insufficient_Memory'Access,
         "decoded payload larger than the stack reports Insufficient_Memory");
   end Register_Tests;

end Zlib_Insufficient_Memory_Tests;
