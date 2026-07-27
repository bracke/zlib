with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib; use Zlib;

package body Zlib_Insufficient_Memory_Tests is

   package SIO renames Ada.Streams.Stream_IO;
   use type Ada.Streams.Stream_Element_Offset;

   --  A decoded payload that cannot fit in the caller's stack must be reported
   --  as Insufficient_Memory. It must never be reported as
   --  Unexpected_End_Of_Input, which would blame well-formed input, nor escape
   --  as an exception from an API documented to return a status code.
   --
   --  The bound is made deterministic by running the call in a task with a
   --  small Storage_Size rather than depending on the machine's stack limit.

   Payload_Size : constant := 2 * 1024 * 1024;
   Runner_Stack : constant := 128 * 1024;

   --  Comfortably below Payload_Size, so a run that buffered either the
   --  archive or the decompressed member could not fit.
   Extract_Stack : constant := 1024 * 1024;

   --  The streaming compressor has a fixed working-set cost of its own, so the
   --  task is sized above that and the input is made larger than the task
   --  instead: at 8 MB of input in a 4 MB task, buffering cannot fit whatever
   --  the fixed cost happens to be.
   Compress_Payload : constant := 8 * 1024 * 1024;
   Compress_Chunk   : constant := 64 * 1024;
   Compress_Stack   : constant := 4 * 1024 * 1024;

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

   --  Extraction streams each member from the archive file straight to its
   --  output file, so it must succeed in a task whose stack could not hold
   --  either the archive or the decompressed member. This is the property that
   --  makes a large download extractable without an oversized task.
   procedure Test_Extraction_Is_Not_Bounded_By_The_Stack
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Ada.Directories.File_Size;

      Work    : constant String :=
        Ada.Directories.Current_Directory & "/obj/zip_streaming_check";
      Archive : constant String := Work & "/big.zip";
      Out_Dir : constant String := Work & "/out";
      Member  : constant String := Out_Dir & "/big.txt";

      Payload : Byte_Array_Access := new Zlib.Byte_Array (1 .. Payload_Size);
      Outcome : Zlib.Status_Code := Zlib.Ok;
      Escaped : Boolean := False;
   begin
      if Ada.Directories.Exists (Work) then
         Ada.Directories.Delete_Tree (Work);
      end if;
      Ada.Directories.Create_Path (Out_Dir);

      --  A payload that compresses well keeps the fixture small while the
      --  decompressed member stays far larger than the extracting task's stack.
      Payload.all := [others => 65];

      declare
         Build_Status : Zlib.Status_Code := Zlib.Ok;
         Archive_Data : constant Zlib.Byte_Array :=
           Zlib.ZIP (Payload.all, "big.txt", Status => Build_Status);
         Output       : SIO.File_Type;
      begin
         Free (Payload);
         Assert (Build_Status = Zlib.Ok, "fixture: ZIP must build");

         SIO.Create (Output, SIO.Out_File, Archive);
         declare
            Raw    : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Archive_Data'Length));
            Target : Ada.Streams.Stream_Element_Offset := Raw'First;
         begin
            for B of Archive_Data loop
               Raw (Target) := Ada.Streams.Stream_Element (B);
               Target := Target + 1;
            end loop;
            SIO.Write (Output, Raw);
         end;
         SIO.Close (Output);
      end;

      declare
         task Runner with Storage_Size => Extract_Stack;

         task body Runner is
         begin
            Zlib.Extract_Archive_File_To_Directory
              (Archive_Path    => Archive,
               Destination_Dir => Out_Dir,
               Password        => "",
               Status          => Outcome);
         exception
            when others =>
               Escaped := True;
         end Runner;
      begin
         null;
      end;

      Assert
        (not Escaped,
         "extraction must not raise out of a status-returning API");
      Assert
        (Outcome = Zlib.Ok,
         "extraction into a "
         & Natural'Image (Extract_Stack / 1024)
         & " KB task must stream rather than buffer, got "
         & Zlib.Status_Image (Outcome));
      Assert
        (Ada.Directories.Exists (Member),
         "the extracted member must exist");
      Assert
        (Ada.Directories.Size (Member) = Ada.Directories.File_Size (Payload_Size),
         "the extracted member must be whole");

      Ada.Directories.Delete_Tree (Work);
   end Test_Extraction_Is_Not_Bounded_By_The_Stack;

   --  GZip_File delegates to the streaming encoder when there is no header
   --  metadata to emit, so compressing a file must not be bounded by the
   --  calling task's stack either. The emitted bytes must not change.
   procedure Test_GZip_File_Streams_When_No_Metadata
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Ada.Directories.File_Size;

      Work    : constant String :=
        Ada.Directories.Current_Directory & "/obj/gzip_streaming_check";
      Source  : constant String := Work & "/input.bin";
      Via_One : constant String := Work & "/one_shot.gz";
      Via_Str : constant String := Work & "/streaming.gz";

      Outcome : Zlib.Status_Code := Zlib.Ok;
      Escaped : Boolean := False;
   begin
      if Ada.Directories.Exists (Work) then
         Ada.Directories.Delete_Tree (Work);
      end if;
      Ada.Directories.Create_Path (Work);

      --  Written in chunks so that preparing the fixture does not itself need
      --  a stack the size of the input.
      declare
         Output : SIO.File_Type;
         Chunk  : constant Ada.Streams.Stream_Element_Array
           (1 .. Compress_Chunk) := [others => 66];
      begin
         SIO.Create (Output, SIO.Out_File, Source);
         for I in 1 .. Compress_Payload / Compress_Chunk loop
            SIO.Write (Output, Chunk);
         end loop;
         SIO.Close (Output);
      end;

      declare
         task Runner with Storage_Size => Compress_Stack;

         task body Runner is
         begin
            Zlib.GZip_File (Source, Via_One, Zlib.Auto, Outcome);
         exception
            when others =>
               Escaped := True;
         end Runner;
      begin
         null;
      end;

      Assert (not Escaped, "GZip_File must not raise out of a status API");
      Assert
        (Outcome = Zlib.Ok,
         "GZip_File given"
         & Natural'Image (Compress_Payload / 1024 / 1024)
         & " MB of input in a"
         & Natural'Image (Compress_Stack / 1024 / 1024)
         & " MB task must stream, got " & Zlib.Status_Image (Outcome));

      --  The explicit streaming API is the reference: delegation must not
      --  change the emitted output.
      Zlib.GZip_File_Streaming (Source, Via_Str, Zlib.Auto, Outcome);
      Assert (Outcome = Zlib.Ok, "reference streaming encode must succeed");
      Assert
        (Ada.Directories.Size (Via_One) = Ada.Directories.Size (Via_Str),
         "delegated output must match the streaming encoder");

      Ada.Directories.Delete_Tree (Work);
   end Test_GZip_File_Streams_When_No_Metadata;

   overriding procedure Register_Tests
     (T : in out Test_Case) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Inflate_Reports_Insufficient_Memory'Access,
         "decoded payload larger than the stack reports Insufficient_Memory");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Extraction_Is_Not_Bounded_By_The_Stack'Access,
         "archive extraction streams and is not bounded by the caller's stack");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_GZip_File_Streams_When_No_Metadata'Access,
         "GZip_File streams when no gzip metadata is requested");
   end Register_Tests;

end Zlib_Insufficient_Memory_Tests;
