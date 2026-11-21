--  Support level: private internal implementation.
--
--  An output file written under a temporary name beside its target and
--  renamed over the target only once it is complete. The temporary is created
--  exclusively (it never opens, truncates or follows anything already there),
--  so whatever was at the target before stays untouched until the finished
--  output replaces it, and a write that fails -- or is abandoned -- removes
--  only the temporary it made.
--
--  The temporary is the target's own name followed by ".zlib-partial-<n>"
--  (".zlib-partial-<n>" alone in the target's directory when the target's
--  name is too long to take the suffix), with n counting up until a name is
--  free, so concurrent writers never share one.
with Ada.Finalization;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;

package Zlib.Staged_Output is

   Output_Failed : exception;
   --  Raised by Create, Write and Commit when the file system refuses the
   --  output: the temporary cannot be created or written, closing it fails
   --  (a full volume often shows only then), or it cannot be renamed over the
   --  target (a directory is there, the directory is not writable, ...). The
   --  temporary is already removed when it propagates. Storage_Error is
   --  propagated as itself.

   type Staged_File is limited private;
   --  One output in progress. Finalization discards an output that was
   --  neither committed nor discarded, so no exit path leaves a temporary.

   procedure Create (Output : in out Staged_File; Target : String);
   --  Start an output that will become Target. Nothing at Target is touched.

   procedure Write (Output : in out Staged_File; Data : Ada.Streams.Stream_Element_Array);
   --  Append Data to the output.

   procedure Write (Output : in out Staged_File; Data : Byte_Array);
   --  Append Data to the output, converted 64 KiB at a time through a fixed
   --  buffer, so no copy of the whole of Data is ever made.

   procedure Commit (Output : in out Staged_File);
   --  Close the output and rename it over its target, replacing whatever
   --  file (or symbolic link, not followed) was there. On failure the target
   --  is left as it was and the temporary is removed.

   procedure Discard (Output : in out Staged_File);
   --  Close and remove the temporary; the target is left as it was. Never
   --  raises; does nothing for an output not started or already committed.

private

   type Staged_File is new Ada.Finalization.Limited_Controlled with record
      File   : Ada.Streams.Stream_IO.File_Type;
      Target : Ada.Strings.Unbounded.Unbounded_String;
      Temp   : Ada.Strings.Unbounded.Unbounded_String;
      Active : Boolean := False;
      --  True while a temporary this output created may be on disk.
   end record;

   overriding procedure Finalize (Output : in out Staged_File);

end Zlib.Staged_Output;
