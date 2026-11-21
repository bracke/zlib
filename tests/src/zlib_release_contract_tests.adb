with Ada.Environment_Variables;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with CryptoLib.Checksums;
with GNAT.OS_Lib;
with Interfaces;
with Zlib;

package body Zlib_Release_Contract_Tests is

   --  The host's temporary folder: /tmp is not a place Windows has.
   function Temp_Root return String is
     (if Ada.Environment_Variables.Exists ("TMPDIR") then Ada.Environment_Variables.Value ("TMPDIR")
      elsif Ada.Environment_Variables.Exists ("TEMP") then Ada.Environment_Variables.Value ("TEMP")
      elsif Ada.Environment_Variables.Exists ("TMP") then Ada.Environment_Variables.Value ("TMP")
      else "/tmp");

   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Directories.File_Kind;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Zlib.Byte;
   use type Zlib.Status_Code;
   use type Zlib.Byte_Array;
   use type Ada.Directories.File_Size;
   package US renames Ada.Strings.Unbounded;

   function CRC32 (Data : Zlib.Byte_Array) return Interfaces.Unsigned_32 is
      State : CryptoLib.Checksums.CRC32_State;
   begin
      CryptoLib.Checksums.CRC32_Reset (State);
      for B of Data loop
         CryptoLib.Checksums.CRC32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.CRC32_Value (State);
   end CRC32;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib release public contract");
   end Name;

   procedure Assert_Bytes_Equal
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert (Actual'Length = Expected'Length, Message & ": length mismatch");
      for I in Expected'Range loop
         Assert
           (Actual (Actual'First + (I - Expected'First)) = Expected (I),
            Message & ": byte mismatch");
      end loop;
   end Assert_Bytes_Equal;

   procedure Delete_If_Exists (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         if Ada.Directories.Kind (Path) = Ada.Directories.Directory then
            Ada.Directories.Delete_Tree (Path);
         else
            Ada.Directories.Delete_File (Path);
         end if;
      end if;
   exception
      when others =>
         null;
   end Delete_If_Exists;

   procedure Write_File (Path : String; Data : Zlib.Byte_Array) is
      File : Ada.Streams.Stream_IO.File_Type;
      Raw  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
   begin
      for I in Data'Range loop
         Raw (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
           Ada.Streams.Stream_Element (Data (I));
      end loop;

      Ada.Streams.Stream_IO.Create
        (File, Ada.Streams.Stream_IO.Out_File, Path);
      Ada.Streams.Stream_IO.Write (File, Raw);
      Ada.Streams.Stream_IO.Close (File);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Write_File;

   function Read_File (Path : String) return Zlib.Byte_Array is
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      declare
         Size : constant Ada.Streams.Stream_Element_Count :=
           Ada.Streams.Stream_Element_Count
             (Ada.Streams.Stream_IO.Size (File));
         Raw  : Ada.Streams.Stream_Element_Array (1 .. Size);
         Last : Ada.Streams.Stream_Element_Offset;
      begin
         Ada.Streams.Stream_IO.Read (File, Raw, Last);
         Ada.Streams.Stream_IO.Close (File);

         declare
            Result : Zlib.Byte_Array (1 .. Natural (Last));
         begin
            for I in Result'Range loop
               Result (I) :=
                 Zlib.Byte (Raw (Ada.Streams.Stream_Element_Offset (I)));
            end loop;
            return Result;
         end;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Read_File;

   function ZIP_U16_At
     (Data : Zlib.Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_16
   is
   begin
      return Interfaces.Unsigned_16 (Data (Pos))
        or Interfaces.Shift_Left (Interfaces.Unsigned_16 (Data (Pos + 1)), 8);
   end ZIP_U16_At;

   function ZIP_U32_At
     (Data : Zlib.Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (Data (Pos))
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 1)), 8)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 2)), 16)
        or Interfaces.Shift_Left (Interfaces.Unsigned_32 (Data (Pos + 3)), 24);
   end ZIP_U32_At;

   function ZIP_U64_At
     (Data : Zlib.Byte_Array;
      Pos  : Natural) return Interfaces.Unsigned_64
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for Offset in 0 .. 7 loop
         Result :=
           Result
           or Interfaces.Shift_Left
                (Interfaces.Unsigned_64 (Data (Pos + Offset)), Offset * 8);
      end loop;
      return Result;
   end ZIP_U64_At;

   function Find_ZIP_Signature
     (Data      : Zlib.Byte_Array;
      Signature : Interfaces.Unsigned_32;
      Start     : Natural) return Natural
   is
   begin
      if Data'Length < 4 or else Start > Data'Last - 3 then
         return 0;
      end if;

      for Pos in Start .. Data'Last - 3 loop
         if ZIP_U32_At (Data, Pos) = Signature then
            return Pos;
         end if;
      end loop;

      return 0;
   end Find_ZIP_Signature;

   procedure Assert_ZIP_Roundtrip
     (Archive         : Zlib.Byte_Array;
      Expected_Name   : String;
      Expected_Method : Interfaces.Unsigned_16;
      Expected_Data   : Zlib.Byte_Array;
      Message         : String)
   is
      Local          : constant Natural := Archive'First;
      Name_Length    : Natural;
      Extra_Length   : Natural;
      Payload_First  : Natural;
      Payload_Length : Natural;
      Status         : Zlib.Status_Code;
   begin
      Assert (Archive'Length >= 76, Message & ": ZIP archive has minimum shape");
      Assert
        (ZIP_U32_At (Archive, Local) = 16#0403_4B50#,
         Message & ": local file header signature");
      Assert
        (ZIP_U16_At (Archive, Local + 8) = Expected_Method,
         Message & ": local compression method");
      Assert
        (ZIP_U32_At (Archive, Local + 14) = CRC32 (Expected_Data),
         Message & ": local CRC32");
      Assert
        (ZIP_U32_At (Archive, Local + 22) =
           Interfaces.Unsigned_32 (Expected_Data'Length),
         Message & ": local uncompressed size");

      Name_Length := Natural (ZIP_U16_At (Archive, Local + 26));
      Extra_Length := Natural (ZIP_U16_At (Archive, Local + 28));
      Assert (Name_Length = Expected_Name'Length, Message & ": entry name length");
      for I in 0 .. Name_Length - 1 loop
         Assert
           (Archive (Local + 30 + I) =
              Zlib.Byte (Character'Pos (Expected_Name (Expected_Name'First + I))),
            Message & ": entry name byte");
      end loop;

      Payload_First := Local + 30 + Name_Length + Extra_Length;
      Payload_Length := Natural (ZIP_U32_At (Archive, Local + 18));
      Assert
        (Payload_First + Payload_Length <= Archive'Last + 1,
         Message & ": payload within archive");

      declare
         Payload : constant Zlib.Byte_Array :=
           (if Payload_Length = 0
            then [1 .. 0 => 0]
            else Archive (Payload_First .. Payload_First + Payload_Length - 1));
      begin
         if Expected_Method = 0 then
            Assert_Bytes_Equal (Payload, Expected_Data, Message & ": stored payload");
         else
            declare
               Plain : constant Zlib.Byte_Array :=
                 Zlib.Inflate_Raw (Payload, Status);
            begin
               Assert (Status = Zlib.Ok, Message & ": raw Deflate payload inflates");
               Assert_Bytes_Equal
                 (Plain, Expected_Data, Message & ": Deflate payload roundtrip");
            end;
         end if;
      end;
   end Assert_ZIP_Roundtrip;

   procedure Test_Root_Public_One_Shot_Compiles
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Plain : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('o')),
         2 => Zlib.Byte (Character'Pos ('k')),
         3 => 16#00#,
         4 => 16#FF#];
      Status : Zlib.Status_Code;
   begin
      declare
         Encoded : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Plain, Status);
      begin
         Assert (Status = Zlib.Ok, "Deflate_Stored must be visible and succeed");

         declare
            Decoded : constant Zlib.Byte_Array := Zlib.Inflate (Encoded, Status);
         begin
            Assert (Status = Zlib.Ok, "Inflate must be visible and succeed");
            Assert_Bytes_Equal (Decoded, Plain, "root public stored one-shot API");
         end;

         declare
            Decoded : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Encoded, Zlib.Zlib_Header, Status);
         begin
            Assert (Status = Zlib.Ok, "Inflate_With_Header must be visible and succeed");
            Assert_Bytes_Equal (Decoded, Plain, "root public explicit zlib one-shot API");
         end;
      end;

      declare
         Encoded : constant Zlib.Byte_Array := Zlib.Deflate_Fixed (Plain, Status);
      begin
         Assert (Status = Zlib.Ok, "Deflate_Fixed must be visible and succeed");

         declare
            Decoded : constant Zlib.Byte_Array := Zlib.Inflate (Encoded, Status);
         begin
            Assert (Status = Zlib.Ok, "Inflate must accept Deflate_Fixed output");
            Assert_Bytes_Equal (Decoded, Plain, "root public fixed one-shot API");
         end;
      end;

      declare
         Encoded : constant Zlib.Byte_Array := Zlib.Deflate_Dynamic (Plain, Status);
      begin
         Assert (Status = Zlib.Ok, "Deflate_Dynamic must be visible and succeed");

         declare
            Decoded : constant Zlib.Byte_Array := Zlib.Inflate (Encoded, Status);
         begin
            Assert (Status = Zlib.Ok, "Inflate must accept Deflate_Dynamic output");
            Assert_Bytes_Equal (Decoded, Plain, "root public dynamic one-shot API");
         end;
      end;
   end Test_Root_Public_One_Shot_Compiles;

   procedure Test_Root_Public_Streaming_Compiles
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Filter   : Zlib.Filter_Type;
      Header_1 : constant Zlib.Header_Type := Zlib.Default;
      Header_2 : constant Zlib.Header_Type := Zlib.Zlib_Header;
      Header_3 : constant Zlib.Header_Type := Zlib.GZip;
      Header_4 : constant Zlib.Header_Type := Zlib.Raw_Deflate;
      Flush_1  : constant Zlib.Flush_Mode := Zlib.No_Flush;
      Flush_2  : constant Zlib.Flush_Mode := Zlib.Finish;
      In_Data  : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 0);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      pragma Unreferenced (Header_1, Header_2, Header_3, Header_4, Flush_1, Flush_2);
   begin
      Assert (not Zlib.Is_Open (Filter), "default filter must be closed");
      Zlib.Inflate_Init (Filter, Header => Zlib.Default);
      Assert (Zlib.Is_Open (Filter), "Inflate_Init must open filter");

      begin
         Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.Finish);
         Assert (False, "Finish on empty stream must raise Zlib_Error");
      exception
         when Zlib.Zlib_Error =>
            null;
      end;

      Assert (Zlib.Is_Open (Filter), "failed filter remains open until Close");
      Zlib.Close (Filter, Ignore_Error => True);
      Assert (not Zlib.Is_Open (Filter), "Close must close filter");
   end Test_Root_Public_Streaming_Compiles;

   procedure Test_Public_Exception_Names_Visible
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Raised_Status : Boolean := False;
      Raised_Zlib   : Boolean := False;
      Filter        : Zlib.Filter_Type;
      Out_Data      : Ada.Streams.Stream_Element_Array (1 .. 0);
      Out_Last      : Ada.Streams.Stream_Element_Offset;
   begin
      begin
         Zlib.Flush (Filter, Out_Data, Out_Last, Zlib.No_Flush);
      exception
         when Zlib.Status_Error =>
            Raised_Status := True;
      end;

      Zlib.Inflate_Init (Filter);
      begin
         Zlib.Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised_Zlib := True;
      end;
      Zlib.Close (Filter, Ignore_Error => True);

      Assert (Raised_Status, "Status_Error name must be publicly catchable");
      Assert (Raised_Zlib, "Zlib_Error name must be publicly catchable");
   end Test_Public_Exception_Names_Visible;

   procedure Test_Root_Public_Compression_Contracts
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Plain : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('a')),
         2 => Zlib.Byte (Character'Pos ('b')),
         3 => Zlib.Byte (Character'Pos ('c')),
         4 => Zlib.Byte (Character'Pos ('a')),
         5 => Zlib.Byte (Character'Pos ('b')),
         6 => Zlib.Byte (Character'Pos ('c'))];
      Status : Zlib.Status_Code;
   begin
      declare
         Zlib_Output : constant Zlib.Byte_Array :=
           Zlib.Deflate (Plain, Mode => Zlib.Auto, Status => Status);
      begin
         Assert (Status = Zlib.Ok, "Deflate Auto must be visible and succeed");

         declare
            Decoded : constant Zlib.Byte_Array := Zlib.Inflate (Zlib_Output, Status);
         begin
            Assert (Status = Zlib.Ok, "Inflate must accept Deflate Auto output");
            Assert_Bytes_Equal (Decoded, Plain, "public one-shot Deflate Auto");
         end;

         declare
            Decoded : constant Zlib.Byte_Array :=
              Zlib.Inflate_Auto (Zlib_Output, Status);
         begin
            Assert (Status = Zlib.Ok, "Inflate_Auto must accept zlib output");
            Assert_Bytes_Equal (Decoded, Plain, "public auto zlib inflate");
         end;
      end;

      declare
         Raw_Output : constant Zlib.Byte_Array :=
           Zlib.Deflate_Raw (Plain, Mode => Zlib.Stored, Status => Status);
      begin
         Assert (Status = Zlib.Ok,
                 "Deflate_Raw Stored must be visible and succeed");

         declare
            Decoded : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Raw_Output, Zlib.Raw_Deflate, Status);
         begin
            Assert (Status = Zlib.Ok, "explicit raw inflate must accept Deflate_Raw Stored output");
            Assert_Bytes_Equal (Decoded, Plain, "public one-shot Deflate_Raw Stored");
         end;
      end;

      declare
         Raw_Auto_Output : constant Zlib.Byte_Array :=
           Zlib.Deflate_Raw (Plain, Mode => Zlib.Auto, Status => Status);
         Decoded : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (Raw_Auto_Output, Zlib.Raw_Deflate, Status);
      begin
         Assert (Status = Zlib.Ok,
                 "Deflate_Raw Auto must be visible and succeed");
         Assert_Bytes_Equal (Decoded, Plain, "public one-shot Deflate_Raw Auto");

         declare
            Auto_Decoded : constant Zlib.Byte_Array :=
              Zlib.Inflate_Auto (Raw_Auto_Output, Status);
         begin
            Assert (Status = Zlib.Ok, "Inflate_Auto must accept raw output");
            Assert_Bytes_Equal
              (Auto_Decoded, Plain, "public auto raw inflate");
         end;
      end;

      declare
         Gzip_Output : constant Zlib.Byte_Array :=
           Zlib.GZip (Plain, Mode => Zlib.Auto, Status => Status);
      begin
         Assert (Status = Zlib.Ok, "GZip Auto must be visible and succeed");

         declare
            Decoded : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Gzip_Output, Zlib.GZip, Status);
         begin
            Assert (Status = Zlib.Ok, "explicit gzip inflate must accept GZip output");
            Assert_Bytes_Equal (Decoded, Plain, "public one-shot GZip Auto");
         end;

         declare
            Decoded : constant Zlib.Byte_Array :=
              Zlib.Inflate_Auto (Gzip_Output, Status);
         begin
            Assert (Status = Zlib.Ok, "Inflate_Auto must accept gzip output");
            Assert_Bytes_Equal (Decoded, Plain, "public auto gzip inflate");
         end;

         declare
            Rejected : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Gzip_Output, Zlib.Zlib_Header, Status);
            pragma Unreferenced (Rejected);
         begin
            Assert (Status /= Zlib.Ok, "Zlib_Header must reject gzip output");
         end;
      end;

      declare
         Inputs : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String ("one"),
            2 => US.To_Unbounded_String ("two")];
         Expected : constant Zlib.Byte_Array :=
           [1 => Zlib.Byte (Character'Pos ('o')),
            2 => Zlib.Byte (Character'Pos ('n')),
            3 => Zlib.Byte (Character'Pos ('e')),
            4 => Zlib.Byte (Character'Pos ('t')),
            5 => Zlib.Byte (Character'Pos ('w')),
            6 => Zlib.Byte (Character'Pos ('o'))];
         Members : constant Zlib.Byte_Array :=
           Zlib.GZip_Members (Inputs, Zlib.Auto, Status);
      begin
         Assert (Status = Zlib.Ok, "GZip_Members must be visible and succeed");
         declare
            Decoded : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header (Members, Zlib.GZip, Status);
         begin
            Assert
              (Status = Zlib.Ok,
               "multi-member gzip output must inflate through default one-shot gzip");
            Assert_Bytes_Equal
              (Decoded, Expected, "public multi-member gzip output");
         end;

         declare
            Rejected : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header
                (Members, Zlib.GZip, Zlib.Single_Member, Status);
            pragma Unreferenced (Rejected);
         begin
            Assert
              (Status /= Zlib.Ok,
               "explicit Single_Member must reject multi-member gzip output");
         end;
      end;

      declare
         Seven_Zip_Output : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Stored (Plain, "payload.bin", Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "Seven_Zip_Stored must be visible and succeed");
         Assert (Seven_Zip_Output'Length > 32, "Seven_Zip_Stored emits an archive");
         Assert
           (Seven_Zip_Output (Seven_Zip_Output'First) = 16#37#
            and then Seven_Zip_Output (Seven_Zip_Output'First + 1) = 16#7A#,
            "Seven_Zip_Stored emits a 7z signature");

         declare
            Seven_Zip_Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip
                (Seven_Zip_Output, "payload.bin", Status);
         begin
            Assert
              (Status = Zlib.Ok,
               "Extract_Seven_Zip alias must be visible and succeed");
            Assert_Bytes_Equal
              (Seven_Zip_Plain, Plain, "public stored 7z roundtrip");
         end;
      end;

      declare
         Seven_Zip_Output : constant Zlib.Byte_Array :=
           Zlib.Seven_Zip_Deflate
             (Plain, "payload.bin", Zlib.Dynamic, Status);
      begin
         Assert
           (Status = Zlib.Ok,
            "Seven_Zip_Deflate must be visible and succeed");
         Assert
           (Seven_Zip_Output (Seven_Zip_Output'First) = 16#37#
            and then Seven_Zip_Output (Seven_Zip_Output'First + 1) = 16#7A#,
            "Seven_Zip_Deflate emits a 7z signature");

         declare
            Seven_Zip_Plain : constant Zlib.Byte_Array :=
              Zlib.Extract_Seven_Zip
                (Seven_Zip_Output, "payload.bin", Status);
         begin
            Assert
              (Status = Zlib.Ok,
               "Extract_Seven_Zip alias must accept Deflate 7z output");
            Assert_Bytes_Equal
              (Seven_Zip_Plain, Plain, "public Deflate 7z roundtrip");
         end;
      end;

      Zlib.Seven_Zip_PPMd_File
        (Temp_Root & "/zlib-release-contract-missing-input",
         Temp_Root & "/zlib-release-contract-ppmd.7z",
         Status);
      Assert
        (Status /= Zlib.Ok,
         "Seven_Zip_PPMd_File must be visible and status-based");

   end Test_Root_Public_Compression_Contracts;

   procedure Test_Root_Public_Streaming_Compression_Compiles
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Filter   : Zlib.Compression_Filter_Type;
      In_Data  : constant Ada.Streams.Stream_Element_Array (1 .. 3) :=
        [1 => 97, 2 => 98, 3 => 99];
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 512);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Assert (not Zlib.Is_Open (Filter), "default compression filter must be closed");

      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Stored);
      Assert (Zlib.Is_Open (Filter), "Deflate_Init must open compression filter");
      Zlib.Compress (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.No_Flush);
      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
      end loop;
      Zlib.Compress_Close (Filter);

      Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Auto);
      Zlib.Compress (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.No_Flush);
      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
      end loop;
      Zlib.Compress_Close (Filter);
      Zlib.Deflate_Init (Filter, Header => Zlib.Raw_Deflate, Mode => Zlib.Stored);
      Zlib.Compress (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.No_Flush);
      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
      end loop;
      Zlib.Compress_Close (Filter);

   end Test_Root_Public_Streaming_Compression_Compiles;

   procedure Test_Root_Public_Seven_Zip_File_List_Contracts
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Base         : constant String := Temp_Root & "/zlib-release-contract-7z-list";
      First_Path   : constant String := Base & "-first.bin";
      Second_Path  : constant String := Base & "-second.bin";
      Archive_Path : constant String := Base & ".7z";
      Output_Dir   : constant String := Base & "-out";
      First_Data   : constant Zlib.Byte_Array :=
        [1 => 16#72#, 2 => 16#6F#, 3 => 16#6F#, 4 => 16#74#];
      Second_Data  : constant Zlib.Byte_Array :=
        [1 => 16#37#, 2 => 16#7A#, 3 => 16#00#, 4 => 16#FF#];
      Input_Paths  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String (First_Path),
         2 => US.To_Unbounded_String (Second_Path)];
      Entry_Names  : constant Zlib.Text_Array :=
        [1 => US.To_Unbounded_String ("first.bin"),
         2 => US.To_Unbounded_String ("nested/second.bin")];
      Status       : Zlib.Status_Code := Zlib.Ok;
   begin
      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Write_File (First_Path, First_Data);
      Write_File (Second_Path, Second_Data);

      Zlib.Seven_Zip_Stored_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "Seven_Zip_Stored_Files must be visible and succeed");
      Assert (Ada.Directories.Exists (Archive_Path), "7z file-list archive exists");

      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "Extract_Seven_Zip_Files alias must be visible and succeed");
      Assert_Bytes_Equal
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")),
         First_Data,
         "public stored 7z file-list first payload");
      Assert_Bytes_Equal
        (Read_File
           (Ada.Directories.Compose
              (Ada.Directories.Compose (Output_Dir, "nested"), "second.bin")),
         Second_Data,
         "public stored 7z file-list nested payload");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Zlib.Seven_Zip_Deflate_Files
        (Input_Paths, Archive_Path, Entry_Names, Zlib.Dynamic, Status);
      Assert
        (Status = Zlib.Ok,
         "Seven_Zip_Deflate_Files must be visible and succeed");
      Assert (Ada.Directories.Exists (Archive_Path), "Deflate 7z file-list archive exists");

      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "Extract_Seven_Zip_Files alias must accept Deflate file lists");
      Assert_Bytes_Equal
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")),
         First_Data,
         "public Deflate 7z file-list first payload");
      Assert_Bytes_Equal
        (Read_File
           (Ada.Directories.Compose
              (Ada.Directories.Compose (Output_Dir, "nested"), "second.bin")),
         Second_Data,
         "public Deflate 7z file-list nested payload");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Zlib.Seven_Zip_Deflate_Files
        (Input_Paths, Archive_Path, Entry_Names, Zlib.Default_Level, Status);
      Assert
        (Status = Zlib.Ok,
         "Seven_Zip_Deflate_Files level overload must be visible and succeed");

      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "Extract_Seven_Zip_Files alias must accept level Deflate file lists");
      Assert_Bytes_Equal
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")),
         First_Data,
         "public level Deflate 7z file-list first payload");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Zlib.Seven_Zip_LZMA_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "Seven_Zip_LZMA_Files must be visible and succeed");

      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "Extract_Seven_Zip_Files alias must accept LZMA file lists");
      Assert_Bytes_Equal
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")),
         First_Data,
         "public LZMA 7z file-list first payload");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Zlib.Seven_Zip_LZMA2_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "Seven_Zip_LZMA2_Files must be visible and succeed");

      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "Extract_Seven_Zip_Files alias must accept LZMA2 file lists");
      Assert_Bytes_Equal
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")),
         First_Data,
         "public LZMA2 7z file-list first payload");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);

      Zlib.Seven_Zip_PPMd_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "Seven_Zip_PPMd_Files must be visible and succeed");

      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok,
         "Extract_Seven_Zip_Files alias must accept PPMd file lists");
      Assert_Bytes_Equal
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")),
         First_Data,
         "public PPMd 7z file-list first payload");

      --  Solid multi-file archives: all entries in one shared folder.
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
      Zlib.Seven_Zip_LZMA_Solid_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok, "Seven_Zip_LZMA_Solid_Files must succeed");
      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "extract solid LZMA file list");
      Assert_Bytes_Equal
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")),
         First_Data, "solid LZMA first payload");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
      Zlib.Seven_Zip_LZMA2_Solid_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok, "Seven_Zip_LZMA2_Solid_Files must succeed");
      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "extract solid LZMA2 file list");
      Assert_Bytes_Equal
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")),
         First_Data, "solid LZMA2 first payload");

      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
      Zlib.Seven_Zip_PPMd_Solid_Files
        (Input_Paths, Archive_Path, Entry_Names, Status);
      Assert
        (Status = Zlib.Ok, "Seven_Zip_PPMd_Solid_Files must succeed");
      Zlib.Extract_Seven_Zip_Files
        (Archive_Path, Output_Dir, Entry_Names, Status);
      Assert (Status = Zlib.Ok, "extract solid PPMd file list");
      Assert_Bytes_Equal
        (Read_File (Ada.Directories.Compose (Output_Dir, "first.bin")),
         First_Data, "solid PPMd first payload");

      Delete_If_Exists (First_Path);
      Delete_If_Exists (Second_Path);
      Delete_If_Exists (Archive_Path);
      Delete_If_Exists (Output_Dir);
   exception
      when others =>
         Delete_If_Exists (First_Path);
         Delete_If_Exists (Second_Path);
         Delete_If_Exists (Archive_Path);
         Delete_If_Exists (Output_Dir);
         raise;
   end Test_Root_Public_Seven_Zip_File_List_Contracts;

   procedure Test_Root_Public_ZIP_Contracts
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Plain       : constant Zlib.Byte_Array :=
        [1 => Zlib.Byte (Character'Pos ('z')),
         2 => Zlib.Byte (Character'Pos ('i')),
         3 => Zlib.Byte (Character'Pos ('p')),
         4 => 16#00#,
         5 => 16#FF#,
         6 => Zlib.Byte (Character'Pos ('!'))];
      Plain_Twice : constant Zlib.Byte_Array :=
        [1  => Zlib.Byte (Character'Pos ('z')),
         2  => Zlib.Byte (Character'Pos ('i')),
         3  => Zlib.Byte (Character'Pos ('p')),
         4  => 16#00#,
         5  => 16#FF#,
         6  => Zlib.Byte (Character'Pos ('!')),
         7  => Zlib.Byte (Character'Pos ('z')),
         8  => Zlib.Byte (Character'Pos ('i')),
         9  => Zlib.Byte (Character'Pos ('p')),
         10 => 16#00#,
         11 => 16#FF#,
         12 => Zlib.Byte (Character'Pos ('!'))];
      Input_Path        : constant String := "zlib-release-contract-zip-input.bin";
      Second_Input_Path : constant String := "zlib-release-contract-gzip-input.bin";
      Output_Path       : constant String := "zlib-release-contract-zip-output.zip";
      Multi_Output_Path : constant String := "zlib-release-contract-zip-multi.zip";
      ZIP64_Output_Path : constant String := "zlib-release-contract-zip64.zip";
      GZip_Output_Path  : constant String := "zlib-release-contract-members.gz";
      Status            : Zlib.Status_Code;
   begin
      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.ZIP (Plain, "nested/payload.bin", Zlib.Stored, Status);
      begin
         Assert (Status = Zlib.Ok, "ZIP Stored one-shot status");
         Assert_ZIP_Roundtrip
           (Archive, "nested/payload.bin", 0, Plain,
            "root public ZIP Stored one-shot API");
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.ZIP (Plain, "payload.bin", Zlib.Dynamic, Status);
      begin
         Assert (Status = Zlib.Ok, "ZIP Deflate one-shot status");
         Assert_ZIP_Roundtrip
           (Archive, "payload.bin", 8, Plain,
            "root public ZIP Deflate one-shot API");
      end;

      declare
         Archive : constant Zlib.Byte_Array :=
           Zlib.ZIP (Plain, "../payload.bin", Zlib.Stored, Status);
      begin
         Assert
           (Status = Zlib.Unsupported_Method,
            "ZIP rejects unsafe traversal entry name");
         Assert (Archive'Length = 0, "unsafe ZIP entry returns empty archive");
      end;

      Write_File (Input_Path, Plain);
      Zlib.ZIP_File
        (Input_Path, Output_Path, "payload.bin", Zlib.Auto, Status);
      Assert (Status = Zlib.Ok, "ZIP_File status");
      Assert_ZIP_Roundtrip
        (Read_File (Output_Path), "payload.bin", 8, Plain,
         "root public ZIP_File API");

      Write_File (Second_Input_Path, Plain);
      declare
         Inputs : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String (Input_Path),
            2 => US.To_Unbounded_String (Second_Input_Path)];
         Names  : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String ("first.bin"),
            2 => US.To_Unbounded_String ("nested/second.bin")];
      begin
         Zlib.ZIP_Files
           (Inputs, Multi_Output_Path, Names, Zlib.Stored, False, Status);
         Assert (Status = Zlib.Ok, "ZIP_Files multi-entry ZIP32 status");
         declare
            Archive      : constant Zlib.Byte_Array := Read_File (Multi_Output_Path);
            First_Local  : constant Natural := Archive'First;
            First_Name   : constant String := "first.bin";
            Second_Local : Natural;
            Central      : Natural;
            EOCD         : Natural;
         begin
            Assert_ZIP_Roundtrip
              (Archive, First_Name, 0, Plain,
               "root public ZIP_Files first entry");
            Second_Local :=
              First_Local + 30 + First_Name'Length + Plain'Length;
            Assert
              (ZIP_U32_At (Archive, Second_Local) = 16#0403_4B50#,
               "ZIP_Files second local header signature");
            Assert
              (ZIP_U16_At (Archive, Second_Local + 8) = 0,
               "ZIP_Files second stored method");
            Assert
              (ZIP_U32_At (Archive, Second_Local + 22) =
                 Interfaces.Unsigned_32 (Plain'Length),
               "ZIP_Files second uncompressed size");
            Central := Find_ZIP_Signature (Archive, 16#0201_4B50#, Archive'First);
            Assert (Central /= 0, "ZIP_Files central directory exists");
            EOCD := Find_ZIP_Signature (Archive, 16#0605_4B50#, Central);
            Assert (EOCD /= 0, "ZIP_Files EOCD exists");
            Assert
              (ZIP_U16_At (Archive, EOCD + 10) = 2,
               "ZIP_Files EOCD entry count");
         end;

         --  Directory members: zero-length Stored entries after the files,
         --  named with a trailing "/", UTF-8 flagged, DOS directory attribute.
         declare
            Dirs_Output_Path : constant String := "zlib-release-contract-zip-dirs.zip";
            Directories : constant Zlib.Text_Array :=
              [1 => US.To_Unbounded_String ("nested"),
               2 => US.To_Unbounded_String ("empty/inner")];
            List_Status : Zlib.Status_Code;
         begin
            Zlib.ZIP_Files
              (Inputs, Dirs_Output_Path, Names, Directories, Zlib.Stored, False, Status);
            Assert (Status = Zlib.Ok, "ZIP_Files with directories status");
            declare
               Archive : constant Zlib.Byte_Array := Read_File (Dirs_Output_Path);
               Listed  : constant Zlib.Archive_Entry_Array := Zlib.List_ZIP_Entries (Archive, List_Status);
               Central : Natural;
               Third   : Natural;
            begin
               Assert (List_Status = Zlib.Ok and then Listed'Length = 4, "four members are listed");
               Assert (US.To_String (Listed (Listed'First + 2).Name) = "nested/"
                       and then Listed (Listed'First + 2).Is_Directory
                       and then US.To_String (Listed (Listed'First + 3).Name) = "empty/inner/"
                       and then Listed (Listed'First + 3).Is_Directory,
                       "the directories follow the files, named with a trailing slash");
               Assert (Listed (Listed'First + 3).Uncompressed_Size = 0
                       and then Listed (Listed'First + 3).Compressed_Size = 0,
                       "a directory member carries no payload");
               Central := Find_ZIP_Signature (Archive, 16#0201_4B50#, Archive'First);
               Third := Central;
               for Skip in 1 .. 2 loop
                  Third := Find_ZIP_Signature (Archive, 16#0201_4B50#, Third + 4);
               end loop;
               Assert (ZIP_U16_At (Archive, Central + 8) = 0, "a file's name carries no UTF-8 flag");
               Assert (ZIP_U16_At (Archive, Third + 8) = 16#0800#, "a directory's name is flagged UTF-8");
               Assert (ZIP_U32_At (Archive, Third + 38) = 16#10#, "a directory has the DOS directory attribute");
            end;

            --  Directories alone make an archive; a name shared by a file and
            --  a directory, or an unsafe directory name, does not.
            declare
               No_Files : constant Zlib.Text_Array (1 .. 0) := [others => <>];
            begin
               Zlib.ZIP_Files (No_Files, Dirs_Output_Path, No_Files, Directories, Status => Status);
               Assert (Status = Zlib.Ok, "a directories-only archive is written");
               declare
                  Listed : constant Zlib.Archive_Entry_Array :=
                    Zlib.List_ZIP_Entries (Read_File (Dirs_Output_Path), List_Status);
               begin
                  Assert (List_Status = Zlib.Ok and then Listed'Length = 2, "both directories are listed");
               end;
               Zlib.ZIP_Files (No_Files, Dirs_Output_Path, No_Files, No_Files, Status => Status);
               Assert (Status = Zlib.Unsupported_Method, "an archive with no members is refused");
            end;
            Zlib.ZIP_Files
              (Inputs, Dirs_Output_Path, Names,
               [1 => US.To_Unbounded_String ("first.bin")], Status => Status);
            Assert (Status = Zlib.Unsupported_Method, "a directory may not share a file's name");
            Zlib.ZIP_Files
              (Inputs, Dirs_Output_Path, Names,
               [1 => US.To_Unbounded_String ("../up")], Status => Status);
            Assert (Status = Zlib.Unsupported_Method, "an unsafe directory name is refused");
            Zlib.ZIP_Files
              (Inputs, Dirs_Output_Path, Names,
               [1 => US.To_Unbounded_String ("d"), 2 => US.To_Unbounded_String ("d")], Status => Status);
            Assert (Status = Zlib.Unsupported_Method, "a repeated directory name is refused");
            if Ada.Directories.Exists (Dirs_Output_Path) then
               Ada.Directories.Delete_File (Dirs_Output_Path);
            end if;
         end;

         Zlib.ZIP_Files
           (Inputs, ZIP64_Output_Path, Names, Zlib.Dynamic, True, Status);
         Assert (Status = Zlib.Ok, "ZIP_Files forced ZIP64 status");
         declare
            Archive      : constant Zlib.Byte_Array := Read_File (ZIP64_Output_Path);
            First_Local  : constant Natural := Archive'First;
            ZIP64_EOCD   : Natural;
            ZIP64_Loc    : Natural;
            EOCD         : Natural;
            Name_Length  : Natural;
            Extra_First  : Natural;
         begin
            Assert
              (ZIP_U16_At (Archive, First_Local + 4) = 45,
               "ZIP64 local version needed");
            Assert
              (ZIP_U32_At (Archive, First_Local + 18) = 16#FFFF_FFFF#,
               "ZIP64 local compressed placeholder");
            Assert
              (ZIP_U32_At (Archive, First_Local + 22) = 16#FFFF_FFFF#,
               "ZIP64 local uncompressed placeholder");
            Name_Length := Natural (ZIP_U16_At (Archive, First_Local + 26));
            Extra_First := First_Local + 30 + Name_Length;
            Assert
              (ZIP_U16_At (Archive, Extra_First) = 16#0001#,
               "ZIP64 local extra id");
            Assert
              (ZIP_U16_At (Archive, Extra_First + 2) = 16,
               "ZIP64 local extra size");
            Assert
              (ZIP_U64_At (Archive, Extra_First + 4) =
                 Interfaces.Unsigned_64 (Plain'Length),
               "ZIP64 local uncompressed size");
            ZIP64_EOCD := Find_ZIP_Signature (Archive, 16#0606_4B50#, Archive'First);
            ZIP64_Loc := Find_ZIP_Signature (Archive, 16#0706_4B50#, Archive'First);
            EOCD := Find_ZIP_Signature (Archive, 16#0605_4B50#, Archive'First);
            Assert (ZIP64_EOCD /= 0, "ZIP64 EOCD exists");
            Assert (ZIP64_Loc /= 0, "ZIP64 locator exists");
            Assert (EOCD /= 0, "ZIP64 fallback EOCD exists");
            Assert
              (ZIP_U64_At (Archive, ZIP64_EOCD + 24) = 2,
               "ZIP64 EOCD entry count");
            Assert
              (ZIP_U16_At (Archive, EOCD + 10) = 16#FFFF#,
               "ZIP64 fallback EOCD count placeholder");
         end;

         Zlib.ZIP_Files
           (Inputs, ZIP64_Output_Path, Names, Zlib.Stored, False, Status);
         Assert (Status = Zlib.Ok, "ZIP_Files rewrites existing output");
      end;

      declare
         Inputs : constant Zlib.Text_Array :=
           [1 => US.To_Unbounded_String (Input_Path),
            2 => US.To_Unbounded_String (Second_Input_Path)];
      begin
         Zlib.GZip_File_Members
           (Inputs, GZip_Output_Path, Zlib.Auto, Status);
         Assert (Status = Zlib.Ok, "GZip_File_Members status");
         declare
            Decoded : constant Zlib.Byte_Array :=
              Zlib.Inflate_With_Header
                (Read_File (GZip_Output_Path),
                 Zlib.GZip,
                 Zlib.Multi_Member,
                 Status);
         begin
            Assert (Status = Zlib.Ok, "GZip_File_Members output inflates");
            Assert_Bytes_Equal
              (Decoded, Plain_Twice, "root public GZip_File_Members API");
         end;
      end;

      Delete_If_Exists (Input_Path);
      Delete_If_Exists (Second_Input_Path);
      Delete_If_Exists (Output_Path);
      Delete_If_Exists (Multi_Output_Path);
      Delete_If_Exists (ZIP64_Output_Path);
      Delete_If_Exists (GZip_Output_Path);
   exception
      when others =>
         Delete_If_Exists (Input_Path);
         Delete_If_Exists (Second_Input_Path);
         Delete_If_Exists (Output_Path);
         Delete_If_Exists (Multi_Output_Path);
         Delete_If_Exists (ZIP64_Output_Path);
         Delete_If_Exists (GZip_Output_Path);
         raise;
   end Test_Root_Public_ZIP_Contracts;

   procedure Test_Status_Image_Full_Release_Contract
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert (Zlib.Status_Image (Zlib.Ok) = "ok", "Ok image");
      Assert (Zlib.Status_Image (Zlib.Invalid_Header) = "invalid zlib header", "Invalid_Header image");
      Assert
        (Zlib.Status_Image (Zlib.Unsupported_Method) =
           "unsupported compression method",
         "Unsupported_Method image");
      Assert
        (Zlib.Status_Image (Zlib.Unsupported_Preset_Dictionary) =
           "unsupported preset dictionary",
         "Unsupported_Preset_Dictionary image");
      Assert (Zlib.Status_Image (Zlib.Invalid_Checksum) = "invalid checksum", "Invalid_Checksum image");
      Assert
        (Zlib.Status_Image (Zlib.Invalid_Block_Type) =
           "invalid or unsupported Deflate block type",
         "Invalid_Block_Type image");
      Assert
        (Zlib.Status_Image (Zlib.Invalid_Stored_Block) =
           "invalid stored Deflate block",
         "Invalid_Stored_Block image");
      Assert (Zlib.Status_Image (Zlib.Invalid_Huffman_Code) = "invalid Huffman code", "Invalid_Huffman_Code image");
      Assert (Zlib.Status_Image (Zlib.Invalid_Distance) = "invalid LZ77 distance", "Invalid_Distance image");
      Assert
        (Zlib.Status_Image (Zlib.Unexpected_End_Of_Input) =
           "unexpected end of input",
         "Unexpected_End_Of_Input image");
      Assert (Zlib.Status_Image (Zlib.Input_File_Error) = "input file error", "Input_File_Error image");
      Assert (Zlib.Status_Image (Zlib.Output_File_Error) = "output file error", "Output_File_Error image");
      Assert (Zlib.Status_Image (Zlib.Cancelled) = "cancelled", "Cancelled image");
   end Test_Status_Image_Full_Release_Contract;

   --  Set a ZIP member's declared uncompressed size in its local header and
   --  its central-directory record, leaving its data and CRC as they are.
   procedure Declare_Uncompressed_Size
     (Image : in out Zlib.Byte_Array;
      Size  : Interfaces.Unsigned_32)
   is
      procedure Put_U32 (Pos : Natural) is
      begin
         for K in 0 .. 3 loop
            Image (Pos + K) := Zlib.Byte (Interfaces.Shift_Right (Size, 8 * K) and 16#FF#);
         end loop;
      end Put_U32;

      Local   : constant Natural := Find_ZIP_Signature (Image, 16#0403_4B50#, Image'First);
      Central : constant Natural := Find_ZIP_Signature (Image, 16#0201_4B50#, Image'First);
   begin
      Assert (Central > Local, "the ZIP has a local header and a central record");
      Put_U32 (Local + 22);
      Put_U32 (Central + 24);
   end Declare_Uncompressed_Size;

   --  A member that decodes to more than it declares is refused before the
   --  excess reaches the disk: a zip bomb cannot fill the destination.
   procedure Test_Extraction_Bounded_By_Declared_Size (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root     : constant String := Temp_Root & "/zlib-release-contract-declared-size";
      Zip_Path : constant String := Root & ".zip";
      Declared : constant := 1_000;
      Status   : Zlib.Status_Code;

      procedure Check (Mode : Zlib.Compression_Mode; Label : String) is
         Data  : constant Zlib.Byte_Array (1 .. 1024 * 1024) := [others => 16#41#];
         Image : Zlib.Byte_Array := Zlib.ZIP (Data, "bomb.bin", Mode, Status);
      begin
         Assert (Status = Zlib.Ok, Label & ": the archive is written");
         Declare_Uncompressed_Size (Image, Declared);
         if Ada.Directories.Exists (Root) then
            Ada.Directories.Delete_Tree (Root);
         end if;
         Ada.Directories.Create_Path (Root);
         Write_File (Zip_Path, Image);

         Zlib.Extract_Archive_File_To_Directory (Zip_Path, Root, "", Status);
         Assert (Status = Zlib.Invalid_Checksum,
                 Label & ": a member larger than declared is refused: " & Zlib.Status_Image (Status));
         Assert (not Ada.Directories.Exists (Root & "/bomb.bin"),
                 Label & ": the refused member leaves no partial file behind");
         Ada.Directories.Delete_File (Zip_Path);
      end Check;
   begin
      Check (Zlib.Dynamic, "Deflate");
      Check (Zlib.Stored, "Stored");
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Test_Extraction_Bounded_By_Declared_Size;

   --  A central directory that breaks off before the count its end record
   --  declares is damaged: extraction, single-member extraction and listing
   --  all report Invalid_Header rather than succeeding on the members before
   --  the break, and a member after the break is not reported as absent.
   procedure Test_Damaged_Central_Directory (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root     : constant String := Temp_Root & "/zlib-release-contract-damaged-cd";
      Sources  : constant String := Root & "-sources";
      Out_Dir  : constant String := Root & "-out";
      Zip_Path : constant String := Root & ".zip";
      Data     : constant Zlib.Byte_Array := [Character'Pos ('x'), Character'Pos ('y')];
      Status   : Zlib.Status_Code;

      procedure Fresh_Output is
      begin
         if Ada.Directories.Exists (Out_Dir) then
            Ada.Directories.Delete_Tree (Out_Dir);
         end if;
         Ada.Directories.Create_Path (Out_Dir);
      end Fresh_Output;

      --  Damage the second central record of Valid, by overrunning name
      --  length or by a wrong signature, and check every reader on it.
      procedure Check (Valid : Zlib.Byte_Array; Overrun : Boolean; Label : String) is
         Image   : Zlib.Byte_Array := Valid;
         First   : constant Natural := Find_ZIP_Signature (Image, 16#0201_4B50#, Image'First);
         Second  : constant Natural := Find_ZIP_Signature (Image, 16#0201_4B50#, First + 46);
      begin
         Assert (First > 0 and then Second > First, Label & ": the archive has a second central record");
         if Overrun then
            Image (Second + 28) := 16#FF#;
            Image (Second + 29) := 16#FF#;
         else
            Image (Second) := 0;
         end if;
         Write_File (Zip_Path, Image);

         Fresh_Output;
         Zlib.Extract_Archive_File_To_Directory (Zip_Path, Out_Dir, "", Status);
         Assert (Status = Zlib.Invalid_Header,
                 Label & ": streamed directory extraction reports the damage: " & Zlib.Status_Image (Status));
         Assert (not Ada.Directories.Exists (Out_Dir & "/c.txt"), Label & ": nothing after the break is written");

         Fresh_Output;
         Zlib.Extract_Archive_To_Directory (Image, Out_Dir, "", Status);
         Assert (Status = Zlib.Invalid_Header,
                 Label & ": in-memory directory extraction reports the damage: " & Zlib.Status_Image (Status));

         Zlib.Extract_Archive_File_Entry_To_File (Zip_Path, "a.txt", Out_Dir & "/one", "", Status);
         Assert (Status = Zlib.Ok, Label & ": a member before the break still extracts: " & Zlib.Status_Image (Status));
         Zlib.Extract_Archive_File_Entry_To_File (Zip_Path, "c.txt", Out_Dir & "/three", "", Status);
         Assert (Status = Zlib.Invalid_Header,
                 Label & ": a member after the break is not called absent: " & Zlib.Status_Image (Status));

         declare
            Plain : constant Zlib.Byte_Array := Zlib.Extract_ZIP (Image, "c.txt", Status);
         begin
            Assert (Status = Zlib.Invalid_Header and then Plain'Length = 0,
                    Label & ": in-memory Extract_ZIP reports the damage: " & Zlib.Status_Image (Status));
         end;

         --  The external entry point, and with a password the decrypting
         --  paths, find the member through the same directory walk.
         for Password in Boolean loop
            declare
               Plain : constant Zlib.Byte_Array :=
                 Zlib.Extract_ZIP_External_Entry (Image, "c.txt", (if Password then "secret" else ""), Status);
            begin
               Assert (Status = Zlib.Invalid_Header and then Plain'Length = 0,
                       Label & ": Extract_ZIP_External_Entry (password " & Password'Image
                       & ") reports the damage: " & Zlib.Status_Image (Status));
            end;
         end loop;

         declare
            Listed : constant Zlib.Archive_Entry_Array := Zlib.List_Archive_File_Entries (Zip_Path, "", Status);
         begin
            Assert (Status = Zlib.Invalid_Header and then Listed'Length = 0,
                    Label & ": listing reports the damage: " & Zlib.Status_Image (Status));
         end;
      end Check;
   begin
      if Ada.Directories.Exists (Sources) then
         Ada.Directories.Delete_Tree (Sources);
      end if;
      Ada.Directories.Create_Path (Sources);
      Write_File (Sources & "/a.txt", Data);
      Write_File (Sources & "/b.txt", Data);
      Write_File (Sources & "/c.txt", Data);
      Zlib.ZIP_Files
        (Input_Paths => [US.To_Unbounded_String (Sources & "/a.txt"),
                         US.To_Unbounded_String (Sources & "/b.txt"),
                         US.To_Unbounded_String (Sources & "/c.txt")],
         Output_Path => Zip_Path,
         Entry_Names => [US.To_Unbounded_String ("a.txt"),
                         US.To_Unbounded_String ("b.txt"),
                         US.To_Unbounded_String ("c.txt")],
         Mode        => Zlib.Stored,
         Status      => Status);
      Assert (Status = Zlib.Ok, "the three-member archive is written");

      declare
         Valid : constant Zlib.Byte_Array := Read_File (Zip_Path);
      begin
         Check (Valid, Overrun => True, Label => "name length overrun");
         Check (Valid, Overrun => False, Label => "bad record signature");

         --  A sound directory without the member is still Unsupported_Method.
         declare
            Plain : constant Zlib.Byte_Array := Zlib.Extract_ZIP_External_Entry (Valid, "zz.txt", "", Status);
         begin
            Assert (Status = Zlib.Unsupported_Method and then Plain'Length = 0,
                    "a member a sound directory lacks is Unsupported_Method: " & Zlib.Status_Image (Status));
         end;

         --  An image with no end record at all has no directory to trust.
         declare
            Cut   : constant Zlib.Byte_Array := Valid (Valid'First .. Valid'Last - 22);
            Plain : constant Zlib.Byte_Array := Zlib.Extract_ZIP_External_Entry (Cut, "a.txt", "secret", Status);
         begin
            Assert (Status = Zlib.Invalid_Header and then Plain'Length = 0,
                    "an image without its end record is Invalid_Header: " & Zlib.Status_Image (Status));
         end;
      end;

      Ada.Directories.Delete_File (Zip_Path);
      Ada.Directories.Delete_Tree (Sources);
      Ada.Directories.Delete_Tree (Out_Dir);
   end Test_Damaged_Central_Directory;

   --  Whether any temporary output is left in Dir (recursively).
   function Has_Partial (Dir : String) return Boolean is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Found  : Boolean := False;
      Mark   : constant String := ".zlib-partial-";
   begin
      Ada.Directories.Start_Search (Search, Dir, "");
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Item);
         begin
            if Name not in "." | ".." then
               if (for some I in Name'First .. Name'Last - Mark'Length + 1 =>
                     Name (I .. I + Mark'Length - 1) = Mark)
               then
                  Found := True;
               elsif Ada.Directories.Kind (Item) = Ada.Directories.Directory
                 and then Has_Partial (Ada.Directories.Full_Name (Item))
               then
                  Found := True;
               end if;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      return Found;
   end Has_Partial;

   function Bytes (Text : String) return Zlib.Byte_Array is
     ([for C of Text => Zlib.Byte (Character'Pos (C))]);

   --  Output goes to a temporary beside its target and is renamed over it
   --  only when complete: a successful extraction replaces a file already
   --  there, while a failure -- of the data, of the file system, or a cancel
   --  -- reports its own status, leaves the old file intact and leaves no
   --  temporary behind. A file system refusal is Output_File_Error.
   procedure Test_Output_Files_Staged (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root     : constant String := Temp_Root & "/zlib-release-contract-staged";
      Sources  : constant String := Root & "-sources";
      Out_Dir  : constant String := Root & "-out";
      Zip_Path : constant String := Root & ".zip";
      Bad_Path : constant String := Root & "-bad.zip";
      Big_Path : constant String := Root & "-big.zip";
      Sz_Path  : constant String := Root & ".7z";
      Old      : constant Zlib.Byte_Array := Bytes ("old contents");
      Fresh    : constant Zlib.Byte_Array := Bytes ("fresh contents");
      Status   : Zlib.Status_Code;
      Polls    : Natural := 0;

      procedure Fresh_Output is
      begin
         if Ada.Directories.Exists (Out_Dir) then
            GNAT.OS_Lib.Set_Writable (Out_Dir);
            Ada.Directories.Delete_Tree (Out_Dir);
         end if;
         Ada.Directories.Create_Path (Out_Dir);
      end Fresh_Output;

      --  Stops a streamed member after its first 64 KiB chunk: poll 1 is
      --  before the member, poll 2 before its first chunk, poll 3 before its
      --  second.
      function Cancel_Mid_Member return Boolean is
      begin
         Polls := Polls + 1;
         return Polls >= 3;
      end Cancel_Mid_Member;

      --  Whether Dir really refuses a new file (it does not for root, or on
      --  Windows, where a read-only folder still takes files).
      function Refuses_New_Files (Dir : String) return Boolean is
         Probe : constant String := Dir & "/probe";
         File  : Ada.Streams.Stream_IO.File_Type;
      begin
         Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Probe);
         Ada.Streams.Stream_IO.Close (File);
         Ada.Directories.Delete_File (Probe);
         return False;
      exception
         when others =>
            return True;
      end Refuses_New_Files;
   begin
      Delete_If_Exists (Sources);
      Ada.Directories.Create_Path (Sources);
      Write_File (Sources & "/a.txt", Fresh);
      Zlib.ZIP_Files
        (Input_Paths => [US.To_Unbounded_String (Sources & "/a.txt")],
         Output_Path => Zip_Path,
         Entry_Names => [US.To_Unbounded_String ("a.txt")],
         Mode        => Zlib.Dynamic,
         Status      => Status);
      Assert (Status = Zlib.Ok, "the archive is written");
      Zlib.Seven_Zip_Stored_File (Sources & "/a.txt", Sz_Path, "a.txt", Status);
      Assert (Status = Zlib.Ok, "the 7z is written: " & Zlib.Status_Image (Status));

      --  Success replaces what was there, streamed, one-member and 7z alike.
      Fresh_Output;
      Write_File (Out_Dir & "/a.txt", Old);
      Zlib.Extract_Archive_File_To_Directory (Zip_Path, Out_Dir, "", Status);
      Assert (Status = Zlib.Ok, "extraction over an existing file: " & Zlib.Status_Image (Status));
      Assert (Read_File (Out_Dir & "/a.txt") = Fresh, "the existing file is replaced");
      Write_File (Out_Dir & "/one", Old);
      Zlib.Extract_Archive_File_Entry_To_File (Zip_Path, "a.txt", Out_Dir & "/one", "", Status);
      Assert (Status = Zlib.Ok and then Read_File (Out_Dir & "/one") = Fresh,
              "one member over an existing Output_Path replaces it: " & Zlib.Status_Image (Status));
      Write_File (Out_Dir & "/seven", Old);
      Zlib.Extract_Archive_File_Entry_To_File (Sz_Path, "a.txt", Out_Dir & "/seven", "", Status);
      Assert (Status = Zlib.Ok and then Read_File (Out_Dir & "/seven") = Fresh,
              "a 7z member over an existing Output_Path replaces it: " & Zlib.Status_Image (Status));
      Assert (not Has_Partial (Out_Dir), "a success leaves no temporary");

      --  A member whose data fails leaves the old file and no temporary.
      declare
         Image : Zlib.Byte_Array := Read_File (Zip_Path);
      begin
         Declare_Uncompressed_Size (Image, 3);
         Write_File (Bad_Path, Image);
      end;
      Fresh_Output;
      Write_File (Out_Dir & "/a.txt", Old);
      Zlib.Extract_Archive_File_To_Directory (Bad_Path, Out_Dir, "", Status);
      Assert (Status = Zlib.Invalid_Checksum, "the bad member fails: " & Zlib.Status_Image (Status));
      Assert (Read_File (Out_Dir & "/a.txt") = Old, "the file already at the target is left intact");
      Write_File (Out_Dir & "/one", Old);
      Zlib.Extract_Archive_File_Entry_To_File (Bad_Path, "a.txt", Out_Dir & "/one", "", Status);
      Assert (Status = Zlib.Invalid_Checksum and then Read_File (Out_Dir & "/one") = Old,
              "a failed member leaves the caller's Output_Path intact: " & Zlib.Status_Image (Status));
      Assert (not Has_Partial (Out_Dir), "a failing member leaves no temporary behind");

      --  A target that is a directory is an output failure, not an archive
      --  fault, on the streamed and the in-memory (7z) paths alike.
      Fresh_Output;
      Ada.Directories.Create_Path (Out_Dir & "/a.txt");
      Zlib.Extract_Archive_File_Entry_To_File (Zip_Path, "a.txt", Out_Dir & "/a.txt", "", Status);
      Assert (Status = Zlib.Output_File_Error,
              "a ZIP member onto a directory is Output_File_Error: " & Zlib.Status_Image (Status));
      Zlib.Extract_Archive_File_To_Directory (Zip_Path, Out_Dir, "", Status);
      Assert (Status = Zlib.Output_File_Error,
              "directory extraction onto a directory is Output_File_Error: " & Zlib.Status_Image (Status));
      Zlib.Extract_Archive_File_Entry_To_File (Sz_Path, "a.txt", Out_Dir & "/a.txt", "", Status);
      Assert (Status = Zlib.Output_File_Error,
              "a 7z member onto a directory is Output_File_Error: " & Zlib.Status_Image (Status));
      Assert (Ada.Directories.Kind (Out_Dir & "/a.txt") = Ada.Directories.Directory, "the directory stays");
      Assert (not Has_Partial (Out_Dir), "an output failure leaves no temporary behind");

      --  A destination that takes no new file: Output_File_Error, and the
      --  file already there is left intact.
      Fresh_Output;
      Write_File (Out_Dir & "/a.txt", Old);
      GNAT.OS_Lib.Set_Non_Writable (Out_Dir);
      if Refuses_New_Files (Out_Dir) then
         Zlib.Extract_Archive_File_To_Directory (Zip_Path, Out_Dir, "", Status);
         Assert (Status = Zlib.Output_File_Error,
                 "an unwritable destination is Output_File_Error: " & Zlib.Status_Image (Status));
         Zlib.Extract_Archive_File_Entry_To_File (Zip_Path, "a.txt", Out_Dir & "/a.txt", "", Status);
         Assert (Status = Zlib.Output_File_Error,
                 "one member into an unwritable folder is Output_File_Error: " & Zlib.Status_Image (Status));
         Zlib.Extract_Archive_File_Entry_To_File (Sz_Path, "a.txt", Out_Dir & "/a.txt", "", Status);
         Assert (Status = Zlib.Output_File_Error,
                 "a 7z member into an unwritable folder is Output_File_Error: " & Zlib.Status_Image (Status));
         Assert (Read_File (Out_Dir & "/a.txt") = Old, "the pre-existing target is left intact");
      end if;
      GNAT.OS_Lib.Set_Writable (Out_Dir);
      Assert (not Has_Partial (Out_Dir), "nothing temporary is left in the unwritable folder");

      --  A cancel in the middle of a streamed member keeps neither the
      --  partial member nor its temporary, and leaves the old file.
      declare
         Large : constant Zlib.Byte_Array (1 .. 200_000) := [for I in 1 .. 200_000 => Zlib.Byte (I mod 251)];
      begin
         Write_File (Sources & "/big.bin", Large);
         Zlib.ZIP_Files
           (Input_Paths => [US.To_Unbounded_String (Sources & "/big.bin")],
            Output_Path => Big_Path,
            Entry_Names => [US.To_Unbounded_String ("big.bin")],
            Mode        => Zlib.Stored,
            Status      => Status);
         Assert (Status = Zlib.Ok, "the large archive is written");
      end;
      Fresh_Output;
      Write_File (Out_Dir & "/big.bin", Old);
      Zlib.Extract_Archive_File_To_Directory (Big_Path, Out_Dir, "", Cancel_Mid_Member'Access, Status);
      Assert (Status = Zlib.Cancelled, "cancelled inside the member: " & Zlib.Status_Image (Status));
      Assert (Polls = 3, "cancelled at the poll before the second chunk");
      Assert (Read_File (Out_Dir & "/big.bin") = Old, "a cancelled member leaves the old file");
      Assert (not Has_Partial (Out_Dir), "a cancelled member leaves no temporary");

      Delete_If_Exists (Out_Dir);
      Delete_If_Exists (Sources);
      Delete_If_Exists (Zip_Path);
      Delete_If_Exists (Bad_Path);
      Delete_If_Exists (Big_Path);
      Delete_If_Exists (Sz_Path);
   end Test_Output_Files_Staged;

   --  A cancel callback stops extraction between members: answering True at
   --  once extracts nothing, answering True after the first member keeps it
   --  and nothing after it.
   procedure Test_Extraction_Cancel (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root     : constant String := Temp_Root & "/zlib-release-contract-cancel";
      Sources  : constant String := Root & "-sources";
      Out_Dir  : constant String := Root & "-out";
      Zip_Path : constant String := Root & ".zip";
      First    : constant Zlib.Byte_Array := [Character'Pos ('o'), Character'Pos ('n'), Character'Pos ('e')];
      Second   : constant Zlib.Byte_Array := [Character'Pos ('t'), Character'Pos ('w'), Character'Pos ('o')];
      Status   : Zlib.Status_Code;
      Polls    : Natural := 0;

      function Cancel_At_Once return Boolean is
      begin
         Polls := Polls + 1;
         return True;
      end Cancel_At_Once;

      --  True once the first member is completely on disk, so the poll before
      --  the second member answers True.
      function Cancel_After_First return Boolean is
        (Ada.Directories.Exists (Out_Dir & "/a.txt")
         and then Ada.Directories.Size (Out_Dir & "/a.txt") = First'Length);

      procedure Fresh_Output is
      begin
         if Ada.Directories.Exists (Out_Dir) then
            Ada.Directories.Delete_Tree (Out_Dir);
         end if;
         Ada.Directories.Create_Path (Out_Dir);
      end Fresh_Output;

      function Is_Empty (Dir : String) return Boolean is
         Search : Ada.Directories.Search_Type;
         Item   : Ada.Directories.Directory_Entry_Type;
         Found  : Boolean := False;
      begin
         Ada.Directories.Start_Search (Search, Dir, "");
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Item);
            if Ada.Directories.Simple_Name (Item) not in "." | ".." then
               Found := True;
            end if;
         end loop;
         Ada.Directories.End_Search (Search);
         return not Found;
      end Is_Empty;
   begin
      if Ada.Directories.Exists (Sources) then
         Ada.Directories.Delete_Tree (Sources);
      end if;
      Ada.Directories.Create_Path (Sources);
      Write_File (Sources & "/a.txt", First);
      Write_File (Sources & "/b.txt", Second);
      Zlib.ZIP_Files
        (Input_Paths => [US.To_Unbounded_String (Sources & "/a.txt"), US.To_Unbounded_String (Sources & "/b.txt")],
         Output_Path => Zip_Path,
         Entry_Names => [US.To_Unbounded_String ("a.txt"), US.To_Unbounded_String ("b.txt")],
         Mode        => Zlib.Stored,
         Status      => Status);
      Assert (Status = Zlib.Ok, "the two-member archive is written");

      Fresh_Output;
      Zlib.Extract_Archive_File_To_Directory (Zip_Path, Out_Dir, "", Cancel_At_Once'Access, Status);
      Assert (Status = Zlib.Cancelled, "cancelled at once: " & Zlib.Status_Image (Status));
      Assert (Polls = 1, "the callback is polled once, before the first member");
      Assert (Is_Empty (Out_Dir), "nothing is extracted");

      Fresh_Output;
      Zlib.Extract_Archive_File_To_Directory (Zip_Path, Out_Dir, "", Cancel_After_First'Access, Status);
      Assert (Status = Zlib.Cancelled, "cancelled after the first member: " & Zlib.Status_Image (Status));
      Assert (Read_File (Out_Dir & "/a.txt") = First, "the first member is extracted whole");
      Assert (not Ada.Directories.Exists (Out_Dir & "/b.txt"), "the second member is not");

      Fresh_Output;
      Zlib.Extract_Archive_File_To_Directory (Zip_Path, Out_Dir, "", Status);
      Assert (Status = Zlib.Ok, "the form without a callback extracts everything");
      Assert (Read_File (Out_Dir & "/b.txt") = Second, "including the second member");

      Ada.Directories.Delete_Tree (Out_Dir);
      Ada.Directories.Delete_Tree (Sources);
      Ada.Directories.Delete_File (Zip_Path);
   end Test_Extraction_Cancel;

   --  A member's name in an archive is the path it is extracted to: a
   --  name written with '\' separators (old Windows tools) lands in its
   --  folder, a ':' is a name's own character where the host stores one,
   --  and nothing leaves the destination.
   procedure Test_Extracted_Entry_Paths (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Colons_Kept : constant Boolean :=
        not Ada.Environment_Variables.Exists ("SystemRoot") and then not Ada.Environment_Variables.Exists ("windir");
      Root    : constant String := Temp_Root & "/zlib-release-contract-entry-paths";
      Status  : Zlib.Status_Code;
      Payload : constant Zlib.Byte_Array := [Character'Pos ('o'), Character'Pos ('k')];

      --  A one-member ZIP whose name is Stored_As: written under a safe name
      --  of the same length, then that name's bytes replaced in the image
      --  (both headers keep it uncompressed; the CRC covers the data only).
      function Archive_Named (Stored_As : String) return Zlib.Byte_Array is
         Safe  : constant String (Stored_As'Range) := [others => 'x'];
         Image : Zlib.Byte_Array := Zlib.ZIP (Payload, Safe, Zlib.Stored, Status);
         Found : Natural := 0;
      begin
         for I in Image'First .. Image'Last - Safe'Length + 1 loop
            if (for all K in 0 .. Safe'Length - 1 => Image (I + K) = Character'Pos ('x')) then
               for K in 0 .. Safe'Length - 1 loop
                  Image (I + K) := Character'Pos (Stored_As (Stored_As'First + K));
               end loop;
               Found := Found + 1;
            end if;
         end loop;
         Assert (Found = 2, "the name is in both headers once");
         return Image;
      end Archive_Named;

      --  Extract an archive holding Stored_As into a fresh folder.
      procedure Extract (Stored_As : String) is
         Zip_Path : constant String := Root & ".zip";
      begin
         if Ada.Directories.Exists (Root) then
            Ada.Directories.Delete_Tree (Root);
         end if;
         Ada.Directories.Create_Path (Root);
         Write_File (Zip_Path, Archive_Named (Stored_As));
         Zlib.Extract_Archive_File_To_Directory (Zip_Path, Root, "", Status);
         Ada.Directories.Delete_File (Zip_Path);
      end Extract;
   begin
      Assert (Zlib.Entry_Path_Name ("dir\file.txt") = "dir/file.txt", "a name with only '\' separates by it");
      Assert (Zlib.Entry_Path_Name ("dir/a\b.txt") = "dir/a\b.txt", "a '\' beside a '/' is left alone");
      Assert (not Zlib.Safe_Entry_Path ("dir/a\b.txt"), "a '\' left in a path is refused");
      Assert (not Zlib.Safe_Entry_Path ("../x") and then not Zlib.Safe_Entry_Path ("/x")
              and then not Zlib.Safe_Entry_Path ("a//b") and then not Zlib.Safe_Entry_Path ("a/./b"),
              "traversal, absolute and empty segments are refused");
      Assert (Zlib.Safe_Entry_Path ("Meeting 10:30.txt") = Colons_Kept,
              "a ':' is a name's own where the host stores it, refused where it is path syntax");

      Extract ("dir\file.txt");
      Assert (Status = Zlib.Ok, "a '\'-separated member extracts: " & Zlib.Status_Image (Status));
      Assert (Ada.Directories.Exists (Root & "/dir/file.txt"), "it lands in its folder");

      Extract ("..\escape.txt");
      Assert (Status /= Zlib.Ok, "a '\'-separated traversal is refused");
      Assert (not Ada.Directories.Exists (Temp_Root & "/escape.txt"), "nothing is written outside");

      if Colons_Kept then
         Extract ("Meeting 10:30.txt");
         Assert (Status = Zlib.Ok, "a member with ':' extracts here: " & Zlib.Status_Image (Status));
         Assert (Ada.Directories.Exists (Root & "/Meeting 10:30.txt"), "under its own name");
      end if;
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
   end Test_Extracted_Entry_Paths;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Root_Public_One_Shot_Compiles'Access,
                                     "external-style root one-shot API compiles");
      Registration.Register_Routine (T, Test_Root_Public_Streaming_Compiles'Access,
                                     "external-style root streaming API compiles");
      Registration.Register_Routine (T, Test_Public_Exception_Names_Visible'Access,
                                     "public exception names are visible");
      Registration.Register_Routine
        (T, Test_Root_Public_Compression_Contracts'Access,
         "external-style root compression API compiles");
      Registration.Register_Routine
        (T, Test_Root_Public_Streaming_Compression_Compiles'Access,
         "external-style root streaming compression API compiles");
      Registration.Register_Routine
        (T, Test_Root_Public_Seven_Zip_File_List_Contracts'Access,
         "external-style root 7z file-list API compiles");
      Registration.Register_Routine
        (T, Test_Root_Public_ZIP_Contracts'Access,
         "external-style root ZIP API compiles");
      Registration.Register_Routine (T, Test_Status_Image_Full_Release_Contract'Access,
                                     "all Status_Image strings match release contract");
      Registration.Register_Routine (T, Test_Extracted_Entry_Paths'Access,
                                     "an extracted member's name is its path below the folder, and only there");
      Registration.Register_Routine (T, Test_Extraction_Bounded_By_Declared_Size'Access,
                                     "a member larger than it declares is refused before the excess is written");
      Registration.Register_Routine (T, Test_Damaged_Central_Directory'Access,
                                     "a central directory that breaks off early is reported, not half extracted");
      Registration.Register_Routine (T, Test_Extraction_Cancel'Access,
                                     "a cancel callback stops directory extraction between members");
      Registration.Register_Routine (T, Test_Output_Files_Staged'Access,
                                     "output is renamed into place only when complete; failures keep the old file");
   end Register_Tests;
end Zlib_Release_Contract_Tests;
