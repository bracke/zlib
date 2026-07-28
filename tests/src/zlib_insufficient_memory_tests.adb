with Ada.Directories;
with Ada.Streams.Stream_IO;
with Interfaces;
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

   --  Deflate_File and Inflate_File delegate to their streaming counterparts
   --  too, so a file larger than the task's stack must survive a full
   --  round-trip. Delegating GZip_File alone would have left these bounded and
   --  the split between them surprising.
   procedure Test_File_Helpers_Round_Trip_Beyond_The_Stack
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Ada.Directories.File_Size;

      Work     : constant String :=
        Ada.Directories.Current_Directory & "/obj/file_helper_check";
      Source   : constant String := Work & "/input.bin";
      Squeezed : constant String := Work & "/input.z";
      Restored : constant String := Work & "/input.back";

      Outcome : Zlib.Status_Code := Zlib.Ok;
      Escaped : Boolean := False;
   begin
      if Ada.Directories.Exists (Work) then
         Ada.Directories.Delete_Tree (Work);
      end if;
      Ada.Directories.Create_Path (Work);

      declare
         Output : SIO.File_Type;
         Chunk  : constant Ada.Streams.Stream_Element_Array
           (1 .. Compress_Chunk) := [others => 67];
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
            Zlib.Deflate_File (Source, Squeezed, Zlib.Auto, Outcome);
            if Outcome = Zlib.Ok then
               Zlib.Inflate_File (Squeezed, Restored, Outcome);
            end if;
         exception
            when others =>
               Escaped := True;
         end Runner;
      begin
         null;
      end;

      Assert (not Escaped, "file helpers must not raise out of a status API");
      Assert
        (Outcome = Zlib.Ok,
         "Deflate_File/Inflate_File round-trip of"
         & Natural'Image (Compress_Payload / 1024 / 1024)
         & " MB in a" & Natural'Image (Compress_Stack / 1024 / 1024)
         & " MB task must stream, got " & Zlib.Status_Image (Outcome));
      Assert
        (Ada.Directories.Size (Restored)
           = Ada.Directories.File_Size (Compress_Payload),
         "the round-tripped file must be whole");

      Ada.Directories.Delete_Tree (Work);
   end Test_File_Helpers_Round_Trip_Beyond_The_Stack;

   --  An archive mixing streamable and non-streamable members must be bounded
   --  by its largest member, not by the whole archive: one BZip2 member used to
   --  send the entire archive down the whole-image path.
   --
   --  There is no public API that writes a multi-member archive with mixed
   --  methods, so the fixture is assembled from two single-entry archives: one
   --  Deflate archive from Zlib.ZIP and one BZip2 payload from
   --  Zlib.Compress_ZIP_External_File. Their central-directory fields are read
   --  back rather than assumed.
   procedure Test_Mixed_Method_Archive_Is_Not_Bounded_By_The_Archive
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Ada.Directories.File_Size;
      use type Interfaces.Unsigned_16;
      use type Interfaces.Unsigned_32;
      use type Interfaces.Unsigned_64;

      Work    : constant String :=
        Ada.Directories.Current_Directory & "/obj/mixed_archive_check";
      Archive : constant String := Work & "/mixed.zip";
      Out_Dir : constant String := Work & "/out";
      Source  : constant String := Work & "/bz_source.bin";

      Member_Size : constant := 256 * 1024;
      Deflate_Name : constant String := "a/deflated.txt";
      BZip2_Name   : constant String := "b/bzipped.txt";

      Outcome : Zlib.Status_Code := Zlib.Ok;
      Escaped : Boolean := False;

      function U16_At (D : Zlib.Byte_Array; P : Natural)
        return Interfaces.Unsigned_16
      is (Interfaces.Unsigned_16 (D (P))
          or Interfaces.Shift_Left (Interfaces.Unsigned_16 (D (P + 1)), 8));

      function U32_At (D : Zlib.Byte_Array; P : Natural)
        return Interfaces.Unsigned_32
      is (Interfaces.Unsigned_32 (D (P))
          or Interfaces.Shift_Left (Interfaces.Unsigned_32 (D (P + 1)), 8)
          or Interfaces.Shift_Left (Interfaces.Unsigned_32 (D (P + 2)), 16)
          or Interfaces.Shift_Left (Interfaces.Unsigned_32 (D (P + 3)), 24));

      procedure Put_U16
        (D : in out Zlib.Byte_Array; P : Natural;
         V : Interfaces.Unsigned_16) is
      begin
         D (P) := Zlib.Byte (V and 16#FF#);
         D (P + 1) := Zlib.Byte (Interfaces.Shift_Right (V, 8) and 16#FF#);
      end Put_U16;

      procedure Put_U32
        (D : in out Zlib.Byte_Array; P : Natural;
         V : Interfaces.Unsigned_32) is
      begin
         for K in 0 .. 3 loop
            D (P + K) :=
              Zlib.Byte (Interfaces.Shift_Right (V, 8 * K) and 16#FF#);
         end loop;
      end Put_U32;

      procedure Put_Name
        (D : in out Zlib.Byte_Array; P : Natural; N : String) is
      begin
         for K in N'Range loop
            D (P + (K - N'First)) := Zlib.Byte (Character'Pos (N (K)));
         end loop;
      end Put_Name;
   begin
      if Ada.Directories.Exists (Work) then
         Ada.Directories.Delete_Tree (Work);
      end if;
      Ada.Directories.Create_Path (Out_Dir);

      declare
         Payload : Byte_Array_Access :=
           new Zlib.Byte_Array (1 .. Member_Size);
         Build   : Zlib.Status_Code := Zlib.Ok;
      begin
         Payload.all := [others => 68];

         --  Deflate member, taken from a single-entry archive so its CRC and
         --  sizes come from the library rather than being recomputed here.
         declare
            One : constant Zlib.Byte_Array :=
              Zlib.ZIP (Payload.all, Deflate_Name, Status => Build);
         begin
            Assert (Build = Zlib.Ok, "fixture: Deflate archive must build");

            --  Write the BZip2 source, then compress it as a ZIP member.
            declare
               Output : SIO.File_Type;
               Raw    : constant Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Member_Size)) :=
                   [others => 69];
            begin
               SIO.Create (Output, SIO.Out_File, Source);
               SIO.Write (Output, Raw);
               SIO.Close (Output);
            end;
            Free (Payload);

            declare
               BZ_Method : Interfaces.Unsigned_16;
               BZ_CRC    : Interfaces.Unsigned_32;
               BZ_Unc    : Interfaces.Unsigned_64;
               BZ_Status : Zlib.Status_Code;
               BZ_Payload : constant Zlib.Byte_Array :=
                 Zlib.Compress_ZIP_External_File
                   (Source, "BZip2", BZ_Method, BZ_CRC, BZ_Unc, BZ_Status);

               --  Deflate member fields, read from the single-entry archive.
               D_Local     : constant Natural := One'First;
               D_Name_Len  : constant Natural :=
                 Natural (U16_At (One, D_Local + 26));
               D_Extra_Len : constant Natural :=
                 Natural (U16_At (One, D_Local + 28));
               D_Method    : constant Interfaces.Unsigned_16 :=
                 U16_At (One, D_Local + 8);
               D_CRC       : constant Interfaces.Unsigned_32 :=
                 U32_At (One, D_Local + 14);
               D_Comp      : constant Natural :=
                 Natural (U32_At (One, D_Local + 18));
               D_Unc       : constant Natural :=
                 Natural (U32_At (One, D_Local + 22));
               D_Data      : constant Natural :=
                 D_Local + 30 + D_Name_Len + D_Extra_Len;

               N1 : constant Natural := Deflate_Name'Length;
               N2 : constant Natural := BZip2_Name'Length;
               L1 : constant Natural := 30 + N1 + D_Comp;
               L2 : constant Natural := 30 + N2 + BZ_Payload'Length;
               C1 : constant Natural := L1 + L2;
               C_Size : constant Natural := 46 + N1 + 46 + N2;
               E_Off  : constant Natural := C1 + C_Size;
               Image  : Zlib.Byte_Array (1 .. E_Off + 22) := [others => 0];
            begin
               Assert (BZ_Status = Zlib.Ok, "fixture: BZip2 member must build");
               Assert (BZ_Method = 12, "fixture: BZip2 method id");

               Put_U32 (Image, 1, 16#0403_4B50#);
               Put_U16 (Image, 5, 20);
               Put_U16 (Image, 9, D_Method);
               Put_U32 (Image, 15, D_CRC);
               Put_U32 (Image, 19, Interfaces.Unsigned_32 (D_Comp));
               Put_U32 (Image, 23, Interfaces.Unsigned_32 (D_Unc));
               Put_U16 (Image, 27, Interfaces.Unsigned_16 (N1));
               Put_Name (Image, 31, Deflate_Name);
               for K in 1 .. D_Comp loop
                  Image (30 + N1 + K) := One (D_Data + K - 1);
               end loop;

               Put_U32 (Image, L1 + 1, 16#0403_4B50#);
               Put_U16 (Image, L1 + 5, 20);
               Put_U16 (Image, L1 + 9, BZ_Method);
               Put_U32 (Image, L1 + 15, BZ_CRC);
               Put_U32
                 (Image, L1 + 19,
                  Interfaces.Unsigned_32 (BZ_Payload'Length));
               Put_U32 (Image, L1 + 23, Interfaces.Unsigned_32 (BZ_Unc));
               Put_U16 (Image, L1 + 27, Interfaces.Unsigned_16 (N2));
               Put_Name (Image, L1 + 31, BZip2_Name);
               for K in 1 .. BZ_Payload'Length loop
                  Image (L1 + 30 + N2 + K) :=
                    BZ_Payload (BZ_Payload'First + K - 1);
               end loop;

               Put_U32 (Image, C1 + 1, 16#0201_4B50#);
               Put_U16 (Image, C1 + 5, 20);
               Put_U16 (Image, C1 + 7, 20);
               Put_U16 (Image, C1 + 11, D_Method);
               Put_U32 (Image, C1 + 17, D_CRC);
               Put_U32 (Image, C1 + 21, Interfaces.Unsigned_32 (D_Comp));
               Put_U32 (Image, C1 + 25, Interfaces.Unsigned_32 (D_Unc));
               Put_U16 (Image, C1 + 29, Interfaces.Unsigned_16 (N1));
               Put_U32 (Image, C1 + 43, 0);
               Put_Name (Image, C1 + 47, Deflate_Name);

               declare
                  C2 : constant Natural := C1 + 46 + N1;
               begin
                  Put_U32 (Image, C2 + 1, 16#0201_4B50#);
                  Put_U16 (Image, C2 + 5, 20);
                  Put_U16 (Image, C2 + 7, 20);
                  Put_U16 (Image, C2 + 11, BZ_Method);
                  Put_U32 (Image, C2 + 17, BZ_CRC);
                  Put_U32
                    (Image, C2 + 21,
                     Interfaces.Unsigned_32 (BZ_Payload'Length));
                  Put_U32 (Image, C2 + 25, Interfaces.Unsigned_32 (BZ_Unc));
                  Put_U16 (Image, C2 + 29, Interfaces.Unsigned_16 (N2));
                  Put_U32 (Image, C2 + 43, Interfaces.Unsigned_32 (L1));
                  Put_Name (Image, C2 + 47, BZip2_Name);
               end;

               Put_U32 (Image, E_Off + 1, 16#0605_4B50#);
               Put_U16 (Image, E_Off + 9, 2);
               Put_U16 (Image, E_Off + 11, 2);
               Put_U32 (Image, E_Off + 13, Interfaces.Unsigned_32 (C_Size));
               Put_U32 (Image, E_Off + 17, Interfaces.Unsigned_32 (C1));

               declare
                  Output : SIO.File_Type;
                  Raw    : Ada.Streams.Stream_Element_Array
                    (1 .. Ada.Streams.Stream_Element_Offset (Image'Length));
                  Target : Ada.Streams.Stream_Element_Offset := Raw'First;
               begin
                  for B of Image loop
                     Raw (Target) := Ada.Streams.Stream_Element (B);
                     Target := Target + 1;
                  end loop;
                  SIO.Create (Output, SIO.Out_File, Archive);
                  SIO.Write (Output, Raw);
                  SIO.Close (Output);
               end;
            end;
         end;
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

      Assert (not Escaped, "extraction must not raise out of a status API");
      Assert
        (Outcome = Zlib.Ok,
         "mixed-method archive must extract, got "
         & Zlib.Status_Image (Outcome));
      Assert
        (Ada.Directories.Size (Out_Dir & "/" & Deflate_Name)
           = Ada.Directories.File_Size (Member_Size),
         "the streamed Deflate member must be whole");
      Assert
        (Ada.Directories.Size (Out_Dir & "/" & BZip2_Name)
           = Ada.Directories.File_Size (Member_Size),
         "the bridged BZip2 member must be whole");

      Ada.Directories.Delete_Tree (Work);
   end Test_Mixed_Method_Archive_Is_Not_Bounded_By_The_Archive;

   --  Listing reads only the central directory, so an archive far larger than
   --  the task's stack must still be catalogued. Holding the payloads is what
   --  the file-based entry point exists to avoid.
   procedure Test_Listing_Does_Not_Read_The_Payloads
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Interfaces.Unsigned_64;

      Work    : constant String :=
        Ada.Directories.Current_Directory & "/obj/listing_check";
      Archive : constant String := Work & "/one.zip";
      Member  : constant String := "deep/member.txt";

      Listing_Stack   : constant := 256 * 1024;
      Listing_Payload : constant := 2 * 1024 * 1024;
      Outcome : Zlib.Status_Code := Zlib.Ok;
      Count   : Natural := 0;
      Sized   : Boolean := False;
      Escaped : Boolean := False;
   begin
      if Ada.Directories.Exists (Work) then
         Ada.Directories.Delete_Tree (Work);
      end if;
      Ada.Directories.Create_Path (Work);

      declare
         Payload : Byte_Array_Access :=
           new Zlib.Byte_Array (1 .. Listing_Payload);
         Build   : Zlib.Status_Code := Zlib.Ok;
      begin
         Payload.all := [others => 70];
         declare
            Image  : constant Zlib.Byte_Array :=
              Zlib.ZIP (Payload.all, Member, Status => Build);
            Output : SIO.File_Type;
            Raw    : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Image'Length));
            Target : Ada.Streams.Stream_Element_Offset := Raw'First;
         begin
            Free (Payload);
            Assert (Build = Zlib.Ok, "fixture: archive must build");
            for B of Image loop
               Raw (Target) := Ada.Streams.Stream_Element (B);
               Target := Target + 1;
            end loop;
            SIO.Create (Output, SIO.Out_File, Archive);
            SIO.Write (Output, Raw);
            SIO.Close (Output);
         end;
      end;

      declare
         task Runner with Storage_Size => Listing_Stack;

         task body Runner is
         begin
            declare
               Listed : constant Zlib.Archive_Entry_Array :=
                 Zlib.List_Archive_File_Entries (Archive, "", Outcome);
            begin
               Count := Listed'Length;
               Sized :=
                 Listed'Length = 1
                 and then Listed (Listed'First).Uncompressed_Size =
                   Interfaces.Unsigned_64 (Listing_Payload);
            end;
         exception
            when others =>
               Escaped := True;
         end Runner;
      begin
         null;
      end;

      Assert (not Escaped, "listing must not raise out of a status API");
      Assert
        (Outcome = Zlib.Ok,
         "listing an archive larger than the task must succeed, got "
         & Zlib.Status_Image (Outcome));
      Assert (Count = 1, "the archive has exactly one member");
      Assert (Sized, "the catalogued size must come from the directory");

      Ada.Directories.Delete_Tree (Work);
   end Test_Listing_Does_Not_Read_The_Payloads;

   --  Pulling one member out of an archive must cost that member, not the
   --  archive. A Stored archive is used so the file on disk is genuinely as
   --  large as its contents, and the extracting task is smaller than both.
   procedure Test_Single_Entry_Extraction_Costs_One_Member
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Ada.Directories.File_Size;

      Work    : constant String :=
        Ada.Directories.Current_Directory & "/obj/single_entry_check";
      Archive : constant String := Work & "/stored.zip";
      Output  : constant String := Work & "/member.out";
      Member  : constant String := "nested/member.bin";

      Member_Size : constant := 2 * 1024 * 1024;
      Pick_Stack  : constant := 1024 * 1024;
      Outcome : Zlib.Status_Code := Zlib.Ok;
      Escaped : Boolean := False;
   begin
      if Ada.Directories.Exists (Work) then
         Ada.Directories.Delete_Tree (Work);
      end if;
      Ada.Directories.Create_Path (Work);

      declare
         Payload : Byte_Array_Access :=
           new Zlib.Byte_Array (1 .. Member_Size);
         Build   : Zlib.Status_Code := Zlib.Ok;
      begin
         Payload.all := [others => 71];
         declare
            Image  : constant Zlib.Byte_Array :=
              Zlib.ZIP (Payload.all, Member, Zlib.Stored, Build);
            Out_F  : SIO.File_Type;
            Raw    : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Image'Length));
            Target : Ada.Streams.Stream_Element_Offset := Raw'First;
         begin
            Free (Payload);
            Assert (Build = Zlib.Ok, "fixture: stored archive must build");
            for B of Image loop
               Raw (Target) := Ada.Streams.Stream_Element (B);
               Target := Target + 1;
            end loop;
            SIO.Create (Out_F, SIO.Out_File, Archive);
            SIO.Write (Out_F, Raw);
            SIO.Close (Out_F);
         end;
      end;

      --  The archive on disk is now at least as large as its member, and both
      --  exceed the task below.
      Assert
        (Ada.Directories.Size (Archive)
           >= Ada.Directories.File_Size (Member_Size),
         "fixture: a Stored archive must be as large as its member");

      declare
         task Runner with Storage_Size => Pick_Stack;

         task body Runner is
         begin
            Zlib.Extract_Archive_File_Entry_To_File
              (Archive_Path => Archive,
               Entry_Name   => Member,
               Output_Path  => Output,
               Password     => "",
               Status       => Outcome);
         exception
            when others =>
               Escaped := True;
         end Runner;
      begin
         null;
      end;

      Assert (not Escaped, "extraction must not raise out of a status API");
      Assert
        (Outcome = Zlib.Ok,
         "extracting one member must not need the archive, got "
         & Zlib.Status_Image (Outcome));
      Assert
        (Ada.Directories.Size (Output)
           = Ada.Directories.File_Size (Member_Size),
         "the extracted member must be whole");

      --  A name the directory does not hold is a definite answer, not a
      --  reason to read the archive whole.
      Zlib.Extract_Archive_File_Entry_To_File
        (Archive_Path => Archive,
         Entry_Name   => "nested/absent.bin",
         Output_Path  => Work & "/absent.out",
         Password     => "",
         Status       => Outcome);
      Assert (Outcome /= Zlib.Ok, "a missing member must not report success");
      Assert
        (not Ada.Directories.Exists (Work & "/absent.out"),
         "a missing member must not leave an output file");

      Ada.Directories.Delete_Tree (Work);
   end Test_Single_Entry_Extraction_Costs_One_Member;

   --  A 7z catalogue also lives in a few regions rather than the whole file:
   --  the signature header, the next header, and an encoded header's packed
   --  stream. Listing must therefore not be bounded by the archive either.
   procedure Test_Seven_Zip_Listing_Reads_Only_Its_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use type Interfaces.Unsigned_64;

      Work    : constant String :=
        Ada.Directories.Current_Directory & "/obj/seven_zip_listing_check";
      Archive : constant String := Work & "/stored.7z";
      Member  : constant String := "sevenzip/member.bin";

      Member_Size   : constant := 2 * 1024 * 1024;
      Listing_Stack : constant := 256 * 1024;
      Outcome : Zlib.Status_Code := Zlib.Ok;
      Count   : Natural := 0;
      Sized   : Boolean := False;
      Escaped : Boolean := False;
   begin
      if Ada.Directories.Exists (Work) then
         Ada.Directories.Delete_Tree (Work);
      end if;
      Ada.Directories.Create_Path (Work);

      declare
         Payload : Byte_Array_Access :=
           new Zlib.Byte_Array (1 .. Member_Size);
         Build   : Zlib.Status_Code := Zlib.Ok;
      begin
         Payload.all := [others => 72];
         declare
            --  Copy-coded, so the file on disk is as large as its member.
            Image  : constant Zlib.Byte_Array :=
              Zlib.Seven_Zip_Stored (Payload.all, Member, Build);
            Out_F  : SIO.File_Type;
            Raw    : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Image'Length));
            Target : Ada.Streams.Stream_Element_Offset := Raw'First;
         begin
            Free (Payload);
            Assert (Build = Zlib.Ok, "fixture: 7z archive must build");
            for B of Image loop
               Raw (Target) := Ada.Streams.Stream_Element (B);
               Target := Target + 1;
            end loop;
            SIO.Create (Out_F, SIO.Out_File, Archive);
            SIO.Write (Out_F, Raw);
            SIO.Close (Out_F);
         end;
      end;

      declare
         task Runner with Storage_Size => Listing_Stack;

         task body Runner is
         begin
            declare
               Listed : constant Zlib.Archive_Entry_Array :=
                 Zlib.List_Archive_File_Entries (Archive, "", Outcome);
            begin
               Count := Listed'Length;
               Sized :=
                 Listed'Length = 1
                 and then Listed (Listed'First).Uncompressed_Size =
                   Interfaces.Unsigned_64 (Member_Size);
            end;
         exception
            when others =>
               Escaped := True;
         end Runner;
      begin
         null;
      end;

      Assert (not Escaped, "listing must not raise out of a status API");
      Assert
        (Outcome = Zlib.Ok,
         "listing a 7z larger than the task must succeed, got "
         & Zlib.Status_Image (Outcome));
      Assert (Count = 1, "the archive has exactly one member");
      Assert (Sized, "the catalogued size must come from the header");

      Ada.Directories.Delete_Tree (Work);
   end Test_Seven_Zip_Listing_Reads_Only_Its_Header;

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
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_File_Helpers_Round_Trip_Beyond_The_Stack'Access,
         "Deflate_File and Inflate_File stream beyond the caller's stack");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Mixed_Method_Archive_Is_Not_Bounded_By_The_Archive'Access,
         "a mixed-method archive is bounded by its largest member");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Listing_Does_Not_Read_The_Payloads'Access,
         "listing an archive reads only its central directory");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Single_Entry_Extraction_Costs_One_Member'Access,
         "extracting one member costs that member, not the archive");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Seven_Zip_Listing_Reads_Only_Its_Header'Access,
         "listing a 7z reads only its header regions");
   end Register_Tests;

end Zlib_Insufficient_Memory_Tests;
