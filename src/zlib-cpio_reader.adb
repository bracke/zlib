with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;

package body Zlib.Cpio_Reader is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element_Offset;

   Header_Size        : constant := 110;
   Payload_Chunk_Size : constant := 8_192;

   --  One indexed member: where its payload sits, its size, whether it is a
   --  directory and whether it is a streamable regular file (only regular
   --  files carry payload bytes), plus the "key=value" attribute string.
   type Member is record
      Name         : Unbounded_String;
      Data_Offset  : Natural := 0;
      Payload      : Natural := 0;
      Is_Directory : Boolean := False;
      Is_Regular   : Boolean := False;
      Meta         : Unbounded_String;
   end record;

   package Member_Vectors is new Ada.Containers.Vectors (Positive, Member);

   function Align_4 (Value : Natural) return Natural is
   begin
      if Value > Natural'Last - 3 then
         return Natural'Last;
      end if;
      return ((Value + 3) / 4) * 4;
   end Align_4;

   function Hex_Value (Value : String; Ok : out Boolean) return Natural is
      Result : Natural := 0;
      Digit  : Natural;
   begin
      Ok := False;
      for C of Value loop
         if C in '0' .. '9' then
            Digit := Character'Pos (C) - Character'Pos ('0');
         elsif C in 'A' .. 'F' then
            Digit := 10 + Character'Pos (C) - Character'Pos ('A');
         elsif C in 'a' .. 'f' then
            Digit := 10 + Character'Pos (C) - Character'Pos ('a');
         else
            return 0;
         end if;

         if Result > (Natural'Last - Digit) / 16 then
            return 0;
         end if;
         Result := Result * 16 + Digit;
      end loop;
      Ok := True;
      return Result;
   end Hex_Value;

   function U64_Image (Value : Interfaces.Unsigned_64) return String is
      Image : constant String := Interfaces.Unsigned_64'Image (Value);
   begin
      if Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end U64_Image;

   function Bytes_To_String
     (Bytes : Ada.Streams.Stream_Element_Array;
      First : Ada.Streams.Stream_Element_Offset;
      Count : Natural)
      return String
   is
      Result : String (1 .. Count);
   begin
      for Index in Result'Range loop
         Result (Index) :=
           Character'Val
             (Bytes (First + Ada.Streams.Stream_Element_Offset (Index - 1)));
      end loop;
      return Result;
   end Bytes_To_String;

   function Read_Exact
     (File  : in out Ada.Streams.Stream_IO.File_Type;
      Count : Natural;
      Bytes : out Ada.Streams.Stream_Element_Array)
      return Boolean
   is
      Last : Ada.Streams.Stream_Element_Offset := 0;
   begin
      if Count = 0 then
         return True;
      end if;
      Ada.Streams.Stream_IO.Read (File, Bytes, Last);
      return Last >= Bytes'First
        and then Natural (Last - Bytes'First + 1) = Count;
   end Read_Exact;

   Mode_Dir     : constant := 16#4000#;
   Mode_Regular : constant := 16#8000#;

   --  Walk the newc/CRC headers of a cpio file on disk, collecting one Member
   --  per real entry (the "TRAILER!!!" sentinel ends the walk).
   procedure Index_Members
     (Archive_Path : String;
      Members      : out Member_Vectors.Vector;
      Status       : out Status_Code)
   is
      File   : Ada.Streams.Stream_IO.File_Type;
      Size   : constant Ada.Directories.File_Size :=
        Ada.Directories.Size (Archive_Path);
      Offset : Natural := 0;

      procedure Fail (Code : Status_Code) is
      begin
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Members := Member_Vectors.Empty_Vector;
         Status := Code;
      end Fail;
   begin
      Members := Member_Vectors.Empty_Vector;

      if Size < Ada.Directories.File_Size (Header_Size)
        or else Size > Ada.Directories.File_Size (Natural'Last)
      then
         Status := Invalid_Header;
         return;
      end if;

      Ada.Streams.Stream_IO.Open
        (File, Ada.Streams.Stream_IO.In_File, Archive_Path);

      while Offset < Natural (Size) loop
         declare
            Header      : Ada.Streams.Stream_Element_Array (1 .. Header_Size);
            Text        : String (1 .. Header_Size);
            Ok          : Boolean;
            Mode        : Natural;
            UID         : Natural;
            GID         : Natural;
            Links       : Natural;
            MTime       : Natural;
            File_Size   : Natural;
            Name_Size   : Natural;
            Check       : Natural;
            Data_Offset : Natural;
            Next_Offset : Natural;
         begin
            if Natural (Size) - Offset < Header_Size then
               Fail (Invalid_Header);
               return;
            end if;

            Ada.Streams.Stream_IO.Set_Index
              (File, Ada.Streams.Stream_IO.Count (Offset + 1));
            if not Read_Exact (File, Header_Size, Header) then
               Fail (Input_File_Error);
               return;
            end if;

            Text := Bytes_To_String (Header, Header'First, Header_Size);
            if Text (1 .. 6) /= "070701" and then Text (1 .. 6) /= "070702" then
               Fail (Invalid_Header);
               return;
            end if;

            Mode      := Hex_Value (Text (15 .. 22), Ok);
            if Ok then UID := Hex_Value (Text (23 .. 30), Ok); end if;
            if Ok then GID := Hex_Value (Text (31 .. 38), Ok); end if;
            if Ok then Links := Hex_Value (Text (39 .. 46), Ok); end if;
            if Ok then MTime := Hex_Value (Text (47 .. 54), Ok); end if;
            if Ok then File_Size := Hex_Value (Text (55 .. 62), Ok); end if;
            if Ok then Name_Size := Hex_Value (Text (95 .. 102), Ok); end if;
            if Ok and then Name_Size = 0 then Ok := False; end if;
            if Ok then Check := Hex_Value (Text (103 .. 110), Ok); end if;
            if not Ok then
               Fail (Invalid_Header);
               return;
            end if;

            if Header_Size > Natural (Size) - Offset
              or else Name_Size > Natural (Size) - Offset - Header_Size
            then
               Fail (Invalid_Header);
               return;
            end if;

            declare
               Name_Bytes : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Name_Size));
               Name_Text  : String (1 .. Name_Size);
               Name       : Unbounded_String;
               Kind_Bits  : constant Natural := Mode - (Mode mod 16#1000#);
            begin
               if not Read_Exact (File, Name_Size, Name_Bytes) then
                  Fail (Input_File_Error);
                  return;
               end if;

               Name_Text :=
                 Bytes_To_String (Name_Bytes, Name_Bytes'First, Name_Size);
               if Name_Text (Name_Text'Last) /= Character'Val (0) then
                  Fail (Invalid_Header);
                  return;
               end if;
               Name :=
                 To_Unbounded_String
                   (Name_Text (Name_Text'First .. Name_Text'Last - 1));
               exit when To_String (Name) = "TRAILER!!!";

               Data_Offset := Align_4 (Offset + Header_Size + Name_Size);
               if Data_Offset > Natural (Size)
                 or else File_Size > Natural (Size) - Data_Offset
               then
                  Fail (Invalid_Header);
                  return;
               end if;
               Next_Offset := Align_4 (Data_Offset + File_Size);
               if Next_Offset > Natural (Size) then
                  Fail (Invalid_Header);
                  return;
               end if;

               declare
                  Meta : constant String :=
                    "cpio.mode=16#" & Text (15 .. 22) & "#"
                    & ";cpio.uid=" & U64_Image (Interfaces.Unsigned_64 (UID))
                    & ";cpio.gid=" & U64_Image (Interfaces.Unsigned_64 (GID))
                    & ";cpio.mtime=" & U64_Image (Interfaces.Unsigned_64 (MTime))
                    & ";cpio.links=" & U64_Image (Interfaces.Unsigned_64 (Links))
                    & ";cpio.check=" & U64_Image (Interfaces.Unsigned_64 (Check))
                    & ";cpio.header_offset="
                    & U64_Image (Interfaces.Unsigned_64 (Offset));
               begin
                  Members.Append
                    (Member'(Name         => Name,
                             Data_Offset  => Data_Offset,
                             Payload      => File_Size,
                             Is_Directory => Kind_Bits = Mode_Dir,
                             Is_Regular   => Kind_Bits = Mode_Regular,
                             Meta         => To_Unbounded_String (Meta)));
               end;

               Offset := Next_Offset;
            end;
         end;
      end loop;

      Ada.Streams.Stream_IO.Close (File);
      Status := Ok;
   exception
      when Storage_Error =>
         Fail (Insufficient_Memory);
      when others =>
         Fail (Input_File_Error);
   end Index_Members;

   function List_Entries
     (Archive_Path : String;
      Status       : out Status_Code) return Archive_Entry_Array
   is
      Members : Member_Vectors.Vector;
   begin
      Index_Members (Archive_Path, Members, Status);
      if Status /= Ok then
         return Empty : Archive_Entry_Array (1 .. 0);
      end if;

      declare
         Result : Archive_Entry_Array (1 .. Natural (Members.Length));
         Index  : Positive := 1;
      begin
         for M of Members loop
            Result (Index).Name := M.Name;
            Result (Index).Is_Directory := M.Is_Directory;
            Result (Index).Compression := 0;
            Result (Index).Uncompressed_Size :=
              Interfaces.Unsigned_64 (M.Payload);
            Result (Index).Compressed_Size :=
              Interfaces.Unsigned_64 (M.Payload);
            Result (Index).CRC_32 := 0;
            Result (Index).Metadata := M.Meta;
            Index := Index + 1;
         end loop;
         return Result;
      end;
   end List_Entries;

   procedure Extract_Entry
     (Archive_Path : String;
      Entry_Name   : String;
      Consumer     : not null access procedure
        (Bytes    : Byte_Array;
         Continue : in out Boolean);
      Status       : out Status_Code)
   is
      Members     : Member_Vectors.Vector;
      Found       : Boolean := False;
      Streamable  : Boolean := False;
      Data_Offset : Natural := 0;
      Remaining   : Natural := 0;
      File        : Ada.Streams.Stream_IO.File_Type;
   begin
      Index_Members (Archive_Path, Members, Status);
      if Status /= Ok then
         return;
      end if;

      for M of Members loop
         if To_String (M.Name) = Entry_Name then
            Found       := True;
            Streamable  := M.Is_Regular;
            Data_Offset := M.Data_Offset;
            Remaining   := M.Payload;
            exit;
         end if;
      end loop;

      if not Found then
         Status := Invalid_Header;   --  no such member
         return;
      elsif not Streamable then
         Status := Unsupported_Method;   --  directory, symlink, device, ...
         return;
      end if;

      Ada.Streams.Stream_IO.Open
        (File, Ada.Streams.Stream_IO.In_File, Archive_Path);
      Ada.Streams.Stream_IO.Set_Index
        (File, Ada.Streams.Stream_IO.Count (Data_Offset + 1));

      while Remaining > 0 loop
         declare
            Count    : constant Natural :=
              Natural'Min (Payload_Chunk_Size, Remaining);
            Raw      : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Last     : Ada.Streams.Stream_Element_Offset := 0;
            Continue : Boolean := True;
         begin
            Ada.Streams.Stream_IO.Read (File, Raw, Last);
            if Last < Raw'First
              or else Natural (Last - Raw'First + 1) /= Count
            then
               Ada.Streams.Stream_IO.Close (File);
               Status := Input_File_Error;
               return;
            end if;

            declare
               Chunk : Byte_Array (0 .. Count - 1);
            begin
               for Index in Chunk'Range loop
                  Chunk (Index) :=
                    Byte (Raw (Raw'First
                          + Ada.Streams.Stream_Element_Offset (Index)));
               end loop;
               Consumer.all (Chunk, Continue);
            end;

            Remaining := Remaining - Count;
            if not Continue then
               Ada.Streams.Stream_IO.Close (File);
               Status := Ok;   --  caller-requested stop is not an error
               return;
            end if;
         end;
      end loop;

      Ada.Streams.Stream_IO.Close (File);
      Status := Ok;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Status := Input_File_Error;
   end Extract_Entry;

end Zlib.Cpio_Reader;
