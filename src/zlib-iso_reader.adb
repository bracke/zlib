with Ada.Containers.Vectors;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;

package body Zlib.Iso_Reader is
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;

   Sector_Size : constant := 2_048;
   PVD_Offset  : constant := 16 * Sector_Size;
   Max_Depth   : constant := 100;
   Chunk_Size  : constant := 32_768;

   type Member is record
      Name         : Unbounded_String;
      Data_Offset  : Natural := 0;
      Payload      : Natural := 0;
      Is_Directory : Boolean := False;
   end record;

   package Member_Vectors is new Ada.Containers.Vectors (Positive, Member);

   function Read_U32_LE (Bytes : Byte_Array; Offset : Natural) return Natural is
      Base : constant Natural := Bytes'First + Offset;
   begin
      return Natural (Bytes (Base))
        + Natural (Bytes (Base + 1)) * 256
        + Natural (Bytes (Base + 2)) * 65_536
        + Natural (Bytes (Base + 3)) * 16_777_216;
   end Read_U32_LE;

   --  Read Count bytes at Offset from the file, or an empty array on any error
   --  or short read.
   function Read_At
     (Path   : String;
      Offset : Natural;
      Count  : Natural)
      return Byte_Array
   is
      File   : Ada.Streams.Stream_IO.File_Type;
      Buffer : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Count));
      Last   : Ada.Streams.Stream_Element_Offset := 0;
   begin
      if Count = 0 then
         return Empty : Byte_Array (1 .. 0);
      end if;

      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      Ada.Streams.Stream_IO.Set_Index
        (File, Ada.Streams.Stream_IO.Positive_Count (Offset + 1));
      Ada.Streams.Stream_IO.Read (File, Buffer, Last);
      Ada.Streams.Stream_IO.Close (File);

      if Last < Buffer'First then
         return Empty : Byte_Array (1 .. 0);
      end if;

      declare
         Length : constant Natural := Natural (Last - Buffer'First + 1);
         Result : Byte_Array (0 .. Length - 1);
      begin
         for Index in Result'Range loop
            Result (Index) :=
              Byte (Buffer (Buffer'First
                    + Ada.Streams.Stream_Element_Offset (Index)));
         end loop;
         return Result;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return Empty : Byte_Array (1 .. 0);
   end Read_At;

   --  Strip an ISO ";version" suffix and trailing spaces from a record name.
   function Clean_Name (Raw : String) return String is
      Last : Natural := Raw'Last;
   begin
      while Last >= Raw'First and then Raw (Last) = ' ' loop
         Last := Last - 1;
      end loop;

      for Index in Raw'First .. Last loop
         if Raw (Index) = ';' then
            if Index = Raw'First then
               return "";
            end if;
            return Raw (Raw'First .. Index - 1);
         end if;
      end loop;

      if Last < Raw'First then
         return "";
      end if;
      return Raw (Raw'First .. Last);
   end Clean_Name;

   function Read_Record_Name
     (Bytes       : Byte_Array;
      Offset      : Natural;
      Name_Length : Natural)
      return String
   is
      Start : constant Natural := Bytes'First + Offset + 33;
      Raw   : String (1 .. Name_Length);
   begin
      for Index in Raw'Range loop
         Raw (Index) := Character'Val (Bytes (Start + Index - 1));
      end loop;
      return Clean_Name (Raw);
   end Read_Record_Name;

   --  Recursively walk a directory extent, appending one Member per named
   --  record (self "." and parent ".." records are skipped).
   procedure Walk_Directory
     (Path    : String;
      Prefix  : String;
      Extent  : Natural;
      Size    : Natural;
      Depth   : Natural;
      Members : in out Member_Vectors.Vector;
      Status  : in out Status_Code)
   is
      Directory : constant Byte_Array :=
        Read_At (Path, Extent * Sector_Size, Size);
      Position  : Natural := 0;
   begin
      if Depth > Max_Depth then
         Status := Invalid_Header;
         return;
      end if;
      if Directory'Length < Size then
         Status := Input_File_Error;
         return;
      end if;

      while Position < Directory'Length loop
         declare
            Record_Length : constant Natural :=
              Natural (Directory (Directory'First + Position));
         begin
            if Record_Length = 0 then
               Position := ((Position / Sector_Size) + 1) * Sector_Size;
            elsif Position + Record_Length > Directory'Length
              or else Record_Length < 34
            then
               Status := Invalid_Header;
               return;
            else
               declare
                  Entry_Extent : constant Natural :=
                    Read_U32_LE (Directory, Position + 2);
                  Entry_Size   : constant Natural :=
                    Read_U32_LE (Directory, Position + 10);
                  Flags        : constant Byte :=
                    Directory (Directory'First + Position + 25);
                  Name_Length  : constant Natural :=
                    Natural (Directory (Directory'First + Position + 32));
               begin
                  if Name_Length = 1
                    and then
                      (Directory (Directory'First + Position + 33) = 0
                       or else Directory (Directory'First + Position + 33) = 1)
                  then
                     null;   --  the "." and ".." self/parent records
                  elsif Name_Length = 0
                    or else 33 + Name_Length > Record_Length
                  then
                     Status := Invalid_Header;
                     return;
                  else
                     declare
                        Name   : constant String :=
                          Read_Record_Name (Directory, Position, Name_Length);
                        Full   : constant String :=
                          (if Prefix'Length = 0 then Name
                           else Prefix & "/" & Name);
                        Is_Dir : constant Boolean :=
                          (Natural (Flags) mod 4) >= 2;
                     begin
                        if Name'Length > 0 then
                           Members.Append
                             (Member'(Name         => To_Unbounded_String (Full),
                                      Data_Offset  => Entry_Extent * Sector_Size,
                                      Payload      => Entry_Size,
                                      Is_Directory => Is_Dir));
                           if Is_Dir and then Entry_Size > 0 then
                              Walk_Directory
                                (Path, Full, Entry_Extent, Entry_Size,
                                 Depth + 1, Members, Status);
                              if Status /= Ok then
                                 return;
                              end if;
                           end if;
                        end if;
                     end;
                  end if;
               end;
               Position := Position + Record_Length;
            end if;
         end;
      end loop;
   end Walk_Directory;

   procedure Index_Members
     (Archive_Path : String;
      Members      : out Member_Vectors.Vector;
      Status       : out Status_Code)
   is
      Header : constant Byte_Array :=
        Read_At (Archive_Path, PVD_Offset, Sector_Size);
   begin
      Members := Member_Vectors.Empty_Vector;
      Status := Ok;

      if Header'Length < Sector_Size
        or else Header (Header'First) /= 1
        or else Header (Header'First + 1) /= Character'Pos ('C')
        or else Header (Header'First + 2) /= Character'Pos ('D')
        or else Header (Header'First + 3) /= Character'Pos ('0')
        or else Header (Header'First + 4) /= Character'Pos ('0')
        or else Header (Header'First + 5) /= Character'Pos ('1')
      then
         Status := Invalid_Header;
         return;
      end if;

      declare
         Root_Length : constant Natural :=
           Natural (Header (Header'First + 156));
         Root_Extent : constant Natural := Read_U32_LE (Header, 156 + 2);
         Root_Size   : constant Natural := Read_U32_LE (Header, 156 + 10);
      begin
         if Root_Length < 34 or else Root_Extent = 0 then
            Status := Invalid_Header;
            return;
         end if;
         Walk_Directory
           (Archive_Path, "", Root_Extent, Root_Size, 0, Members, Status);
         if Status /= Ok then
            Members := Member_Vectors.Empty_Vector;
         end if;
      end;
   exception
      when Storage_Error =>
         Members := Member_Vectors.Empty_Vector;
         Status := Insufficient_Memory;
      when others =>
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
            Result (Index).Is_Directory := M.Is_Directory;
            Result (Index).Compression := 0;
            Result (Index).Uncompressed_Size :=
              Interfaces.Unsigned_64 (M.Payload);
            Result (Index).Compressed_Size :=
              Interfaces.Unsigned_64 (M.Payload);
            Result (Index).CRC_32 := 0;
            Result (Index).Metadata := To_Unbounded_String ("iso9660");
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
      Members      : Member_Vectors.Vector;
      Found        : Boolean := False;
      Is_Directory : Boolean := False;
      Data_Offset  : Natural := 0;
      Remaining    : Natural := 0;
      File         : Ada.Streams.Stream_IO.File_Type;
   begin
      Index_Members (Archive_Path, Members, Status);
      if Status /= Ok then
         return;
      end if;

      for M of Members loop
         if To_String (M.Name) = Entry_Name then
            Found        := True;
            Is_Directory := M.Is_Directory;
            Data_Offset  := M.Data_Offset;
            Remaining    := M.Payload;
            exit;
         end if;
      end loop;

      if not Found then
         Status := Invalid_Header;   --  no such member
         return;
      elsif Is_Directory then
         Status := Unsupported_Method;   --  a directory has no payload
         return;
      end if;

      Ada.Streams.Stream_IO.Open
        (File, Ada.Streams.Stream_IO.In_File, Archive_Path);
      Ada.Streams.Stream_IO.Set_Index
        (File, Ada.Streams.Stream_IO.Positive_Count (Data_Offset + 1));

      while Remaining > 0 loop
         declare
            Count    : constant Natural := Natural'Min (Chunk_Size, Remaining);
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

end Zlib.Iso_Reader;
