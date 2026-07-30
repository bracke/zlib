with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;

package body Zlib.Ar_Reader is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element_Offset;

   Global_Header_Size : constant := 8;
   Member_Header_Size : constant := 60;
   Payload_Chunk_Size : constant := 8_192;

   --  One indexed member: where its payload sits in the file, how big it is,
   --  whether it is a housekeeping record (symbol table / long-name table)
   --  rather than a real file, and the "key=value" attribute string.
   type Member is record
      Name        : Unbounded_String;
      Data_Offset : Natural := 0;
      Payload     : Natural := 0;
      Is_Record   : Boolean := False;
      Meta        : Unbounded_String;
   end record;

   package Member_Vectors is new Ada.Containers.Vectors (Positive, Member);

   function Trim_Spaces (Value : String) return String is
      Last : Natural := Value'Last;
   begin
      while Last >= Value'First and then Value (Last) = ' ' loop
         if Last = Value'First then
            return "";
         end if;
         Last := Last - 1;
      end loop;
      return Value (Value'First .. Last);
   end Trim_Spaces;

   function Trim_Name (Value : String) return String is
      Trimmed : constant String := Trim_Spaces (Value);
   begin
      if Trimmed'Length > 0 and then Trimmed (Trimmed'Last) = '/' then
         return Trimmed (Trimmed'First .. Trimmed'Last - 1);
      end if;
      return Trimmed;
   end Trim_Name;

   function Decimal_Value (Value : String; Ok : out Boolean) return Natural is
      Result : Natural := 0;
      Seen   : Boolean := False;
   begin
      Ok := False;
      for C of Trim_Spaces (Value) loop
         if C in '0' .. '9' then
            Seen := True;
            if Result > (Natural'Last - (Character'Pos (C) - Character'Pos ('0'))) / 10 then
               return 0;
            end if;
            Result := Result * 10 + Character'Pos (C) - Character'Pos ('0');
         else
            return 0;
         end if;
      end loop;
      Ok := Seen;
      return Result;
   end Decimal_Value;

   function Octal_Text (Value : String) return String is
      Trimmed : constant String := Trim_Spaces (Value);
   begin
      if Trimmed'Length = 0 then
         return "";
      end if;
      return "8#" & Trimmed & "#";
   end Octal_Text;

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

   --  Resolve a GNU "/N" long name against the "//" long-name table.
   function Long_Name
     (Table : String;
      Token : String)
      return String
   is
      Ok     : Boolean;
      Offset : constant Natural := Decimal_Value (Token, Ok);
      Last   : Natural;
   begin
      if not Ok or else Offset >= Table'Length then
         return "";
      end if;

      Last := Table'First + Offset;
      while Last <= Table'Last
        and then Table (Last) /= '/'
        and then Table (Last) /= ASCII.LF
      loop
         Last := Last + 1;
      end loop;

      if Last <= Table'First + Offset then
         return "";
      end if;
      return Table (Table'First + Offset .. Last - 1);
   end Long_Name;

   --  Walk the member headers of an "ar" file on disk, collecting one Member
   --  per header. The file is opened and closed here; payloads are not read
   --  (except the "//" long-name table, which resolves later members' names).
   procedure Index_Members
     (Archive_Path : String;
      Members      : out Member_Vectors.Vector;
      Status       : out Status_Code)
   is
      File       : Ada.Streams.Stream_IO.File_Type;
      Size       : constant Ada.Directories.File_Size :=
        Ada.Directories.Size (Archive_Path);
      Offset     : Natural := Global_Header_Size;
      Long_Names : Unbounded_String;
   begin
      Members := Member_Vectors.Empty_Vector;

      if Size < Ada.Directories.File_Size (Global_Header_Size)
        or else Size > Ada.Directories.File_Size (Natural'Last)
      then
         Status := Invalid_Header;
         return;
      end if;

      Ada.Streams.Stream_IO.Open
        (File, Ada.Streams.Stream_IO.In_File, Archive_Path);

      declare
         Magic : Ada.Streams.Stream_Element_Array (1 .. Global_Header_Size);
      begin
         if not Read_Exact (File, Global_Header_Size, Magic)
           or else Bytes_To_String (Magic, Magic'First, Global_Header_Size)
                     /= "!<arch>" & ASCII.LF
         then
            Ada.Streams.Stream_IO.Close (File);
            Status := Invalid_Header;
            return;
         end if;
      end;

      while Offset < Natural (Size) loop
         declare
            Header       : Ada.Streams.Stream_Element_Array
              (1 .. Member_Header_Size);
            Name_Raw     : String (1 .. 16);
            MTime_Raw    : String (1 .. 12);
            UID_Raw      : String (1 .. 6);
            GID_Raw      : String (1 .. 6);
            Mode_Raw     : String (1 .. 8);
            Size_Raw     : String (1 .. 10);
            Size_Ok      : Boolean;
            Member_Size  : Natural;
            Data_Offset  : Natural;
            Payload_Size : Natural;
            Name         : Unbounded_String;
            Is_Record    : Boolean := False;
         begin
            if Natural (Size) - Offset < Member_Header_Size then
               Ada.Streams.Stream_IO.Close (File);
               Status := Invalid_Header;
               return;
            end if;

            if not Read_Exact (File, Member_Header_Size, Header) then
               Ada.Streams.Stream_IO.Close (File);
               Status := Input_File_Error;
               return;
            end if;

            if Character'Val (Header (59)) /= '`'
              or else Character'Val (Header (60)) /= ASCII.LF
            then
               Ada.Streams.Stream_IO.Close (File);
               Status := Invalid_Header;
               return;
            end if;

            Name_Raw  := Bytes_To_String (Header, 1, 16);
            MTime_Raw := Bytes_To_String (Header, 17, 12);
            UID_Raw   := Bytes_To_String (Header, 29, 6);
            GID_Raw   := Bytes_To_String (Header, 35, 6);
            Mode_Raw  := Bytes_To_String (Header, 41, 8);
            Size_Raw  := Bytes_To_String (Header, 49, 10);
            Member_Size := Decimal_Value (Size_Raw, Size_Ok);
            if not Size_Ok
              or else Offset + Member_Header_Size > Natural (Size)
              or else Member_Size > Natural (Size) - Offset - Member_Header_Size
            then
               Ada.Streams.Stream_IO.Close (File);
               Status := Invalid_Header;
               return;
            end if;

            Data_Offset  := Offset + Member_Header_Size;
            Payload_Size := Member_Size;

            declare
               Raw_Name : constant String := Trim_Spaces (Name_Raw);
            begin
               if Raw_Name = "/" then
                  Name := To_Unbounded_String ("ar.symbol_table");
                  Is_Record := True;
               elsif Raw_Name = "//" then
                  declare
                     Table_Bytes : Ada.Streams.Stream_Element_Array
                       (1 .. Ada.Streams.Stream_Element_Offset (Member_Size));
                  begin
                     if not Read_Exact (File, Member_Size, Table_Bytes) then
                        Ada.Streams.Stream_IO.Close (File);
                        Status := Input_File_Error;
                        return;
                     end if;
                     Long_Names :=
                       To_Unbounded_String
                         (Bytes_To_String
                            (Table_Bytes, Table_Bytes'First, Member_Size));
                     Name := To_Unbounded_String ("ar.long_names");
                     Is_Record := True;
                  end;
               elsif Raw_Name'Length > 1
                 and then Raw_Name (Raw_Name'First) = '/'
                 and then Raw_Name (Raw_Name'First + 1) in '0' .. '9'
               then
                  Name :=
                    To_Unbounded_String
                      (Long_Name
                         (To_String (Long_Names),
                          Raw_Name (Raw_Name'First + 1 .. Raw_Name'Last)));
                  if Length (Name) = 0 then
                     Ada.Streams.Stream_IO.Close (File);
                     Status := Invalid_Header;
                     return;
                  end if;
               elsif Raw_Name'Length > 3
                 and then Raw_Name (Raw_Name'First .. Raw_Name'First + 2) = "#1/"
               then
                  declare
                     Name_Size_Ok : Boolean;
                     Name_Size    : constant Natural :=
                       Decimal_Value
                         (Raw_Name (Raw_Name'First + 3 .. Raw_Name'Last),
                          Name_Size_Ok);
                     Name_Bytes   : Ada.Streams.Stream_Element_Array
                       (1 .. Ada.Streams.Stream_Element_Offset (Name_Size));
                  begin
                     if not Name_Size_Ok or else Name_Size > Member_Size then
                        Ada.Streams.Stream_IO.Close (File);
                        Status := Invalid_Header;
                        return;
                     elsif not Read_Exact (File, Name_Size, Name_Bytes) then
                        Ada.Streams.Stream_IO.Close (File);
                        Status := Input_File_Error;
                        return;
                     end if;
                     Name :=
                       To_Unbounded_String
                         (Bytes_To_String
                            (Name_Bytes, Name_Bytes'First, Name_Size));
                     Data_Offset  := Data_Offset + Name_Size;
                     Payload_Size := Member_Size - Name_Size;
                  end;
               else
                  Name := To_Unbounded_String (Trim_Name (Name_Raw));
               end if;
            end;

            declare
               Meta : constant String :=
                 "ar.size=" & U64_Image (Interfaces.Unsigned_64 (Payload_Size))
                 & ";ar.header_offset="
                 & U64_Image (Interfaces.Unsigned_64 (Offset))
                 & ";ar.mtime=" & Trim_Spaces (MTime_Raw)
                 & ";ar.uid=" & Trim_Spaces (UID_Raw)
                 & ";ar.gid=" & Trim_Spaces (GID_Raw)
                 & ";ar.mode=" & Octal_Text (Mode_Raw)
                 & (if Is_Record then ";ar.record=1" else "");
            begin
               Members.Append
                 (Member'(Name        => Name,
                          Data_Offset => Data_Offset,
                          Payload     => Payload_Size,
                          Is_Record   => Is_Record,
                          Meta        => To_Unbounded_String (Meta)));
            end;

            Offset := Offset + Member_Header_Size + Member_Size;
            if Offset mod 2 = 1 then
               Offset := Offset + 1;
            end if;
            exit when Offset > Natural (Size);
            Ada.Streams.Stream_IO.Set_Index
              (File, Ada.Streams.Stream_IO.Count (Offset + 1));
         end;
      end loop;

      Ada.Streams.Stream_IO.Close (File);
      Status := Ok;
   exception
      when Storage_Error =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Members := Member_Vectors.Empty_Vector;
         Status := Insufficient_Memory;
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Members := Member_Vectors.Empty_Vector;
         Status := Input_File_Error;
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
            Result (Index).Is_Directory := False;
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
            Data_Offset := M.Data_Offset;
            Remaining   := M.Payload;
            exit;
         end if;
      end loop;

      if not Found then
         Status := Invalid_Header;   --  no such member
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

end Zlib.Ar_Reader;
