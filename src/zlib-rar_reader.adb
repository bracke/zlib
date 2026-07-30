with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Interfaces;

with CryptoLib.Checksums;

package body Zlib.Rar_Reader is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   Marker_Size              : constant := 7;
   Base_Header_Size         : constant := 7;
   File_Header_Payload_Size : constant := 25;
   Payload_Chunk_Size       : constant := 8_192;

   Block_File : constant := 16#74#;
   Block_End  : constant := 16#7B#;

   No_Flags       : constant Interfaces.Unsigned_16 := 0;
   Flag_Add_Size  : constant Interfaces.Unsigned_16 := 16#8000#;
   Flag_Large     : constant Interfaces.Unsigned_16 := 16#0100#;
   Flag_Directory : constant Interfaces.Unsigned_16 := 16#00E0#;
   Flag_Encrypted : constant Interfaces.Unsigned_16 := 16#0004#;

   Method_Store : constant := 16#30#;

   type Member is record
      Name        : Unbounded_String;
      Data_Offset : Natural := 0;
      Payload     : Natural := 0;
      Streamable  : Boolean := False;
      CRC         : Interfaces.Unsigned_32 := 0;
      Meta        : Unbounded_String;
      Compression : Interfaces.Unsigned_16 := 0;
   end record;

   package Member_Vectors is new Ada.Containers.Vectors (Positive, Member);

   function Byte_At
     (Bytes : Ada.Streams.Stream_Element_Array;
      Index : Natural)
      return Natural
   is (Natural (Bytes (Bytes'First + Ada.Streams.Stream_Element_Offset (Index))));

   function U16_LE
     (Bytes : Ada.Streams.Stream_Element_Array;
      Index : Natural)
      return Natural
   is (Byte_At (Bytes, Index) + Byte_At (Bytes, Index + 1) * 256);

   function U32_LE
     (Bytes : Ada.Streams.Stream_Element_Array;
      Index : Natural)
      return Interfaces.Unsigned_64
   is (Interfaces.Unsigned_64 (Byte_At (Bytes, Index))
       + Interfaces.Unsigned_64 (Byte_At (Bytes, Index + 1)) * 16#100#
       + Interfaces.Unsigned_64 (Byte_At (Bytes, Index + 2)) * 16#1_0000#
       + Interfaces.Unsigned_64 (Byte_At (Bytes, Index + 3)) * 16#100_0000#);

   function U64_From_High_Low
     (High : Interfaces.Unsigned_64;
      Low  : Interfaces.Unsigned_64)
      return Interfaces.Unsigned_64
   is (High * 16#1_0000_0000# + Low);

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

   function Hex2 (Value : Natural) return String is
      Hex_Digits : constant String := "0123456789ABCDEF";
   begin
      return Hex_Digits (Hex_Digits'First + (Value / 16) mod 16)
        & Hex_Digits (Hex_Digits'First + Value mod 16);
   end Hex2;

   function U64_Image (Value : Interfaces.Unsigned_64) return String is
      Image : constant String := Interfaces.Unsigned_64'Image (Value);
   begin
      if Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end U64_Image;

   function Is_Rar4_Marker
     (Bytes : Ada.Streams.Stream_Element_Array)
      return Boolean
   is (Bytes'Length = Marker_Size
       and then Byte_At (Bytes, 0) = 16#52#
       and then Byte_At (Bytes, 1) = 16#61#
       and then Byte_At (Bytes, 2) = 16#72#
       and then Byte_At (Bytes, 3) = 16#21#
       and then Byte_At (Bytes, 4) = 16#1A#
       and then Byte_At (Bytes, 5) = 16#07#
       and then Byte_At (Bytes, 6) = 16#00#);

   --  Walk the RAR4 block chain, collecting one Member per file header. The
   --  chain must end with an End_Of_Archive block.
   procedure Index_Members
     (Archive_Path : String;
      Members      : out Member_Vectors.Vector;
      Status       : out Status_Code)
   is
      File    : Ada.Streams.Stream_IO.File_Type;
      Size    : constant Ada.Directories.File_Size :=
        Ada.Directories.Size (Archive_Path);
      Offset  : Natural := Marker_Size;
      Saw_End : Boolean := False;

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
      Status := Ok;

      if Size < Ada.Directories.File_Size (Marker_Size + Base_Header_Size)
        or else Size > Ada.Directories.File_Size (Natural'Last)
      then
         Status := Invalid_Header;
         return;
      end if;

      Ada.Streams.Stream_IO.Open
        (File, Ada.Streams.Stream_IO.In_File, Archive_Path);

      declare
         Marker : Ada.Streams.Stream_Element_Array (1 .. Marker_Size);
      begin
         if not Read_Exact (File, Marker_Size, Marker) then
            Fail (Input_File_Error);
            return;
         elsif not Is_Rar4_Marker (Marker) then
            Fail (Unsupported_Method);   --  not RAR4 (e.g. RAR5)
            return;
         end if;
      end;

      while Offset < Natural (Size) loop
         declare
            Header       : Ada.Streams.Stream_Element_Array
              (1 .. Base_Header_Size);
            Header_Type  : Natural;
            Flags        : Interfaces.Unsigned_16;
            Header_Size  : Natural;
            Add_Size     : Interfaces.Unsigned_64 := 0;
            Header_Start : constant Natural := Offset;
         begin
            if Natural (Size) - Offset < Base_Header_Size then
               Fail (Invalid_Header);
               return;
            end if;

            Ada.Streams.Stream_IO.Set_Index
              (File, Ada.Streams.Stream_IO.Count (Offset + 1));
            if not Read_Exact (File, Base_Header_Size, Header) then
               Fail (Input_File_Error);
               return;
            end if;

            Header_Type := Byte_At (Header, 2);
            Flags       := Interfaces.Unsigned_16 (U16_LE (Header, 3));
            Header_Size := U16_LE (Header, 5);
            if Header_Size < Base_Header_Size
              or else Header_Size > Natural (Size) - Offset
            then
               Fail (Invalid_Header);
               return;
            end if;

            if (Flags and Flag_Add_Size) /= No_Flags then
               declare
                  Add : Ada.Streams.Stream_Element_Array (1 .. 4);
               begin
                  if not Read_Exact (File, 4, Add) then
                     Fail (Input_File_Error);
                     return;
                  end if;
                  Add_Size := U32_LE (Add, 0);
               end;
            end if;

            if Header_Type = Block_End then
               Saw_End := True;
               exit;
            elsif Header_Type = Block_File then
               declare
                  Body_Size    : constant Natural :=
                    Header_Size - Base_Header_Size;
                  Pack_Low     : Interfaces.Unsigned_64;
                  Unpack_Low   : Interfaces.Unsigned_64;
                  Pack_Size    : Interfaces.Unsigned_64;
                  Unpack_Size  : Interfaces.Unsigned_64;
                  File_CRC     : Interfaces.Unsigned_64;
                  Method       : Natural;
                  Name_Size    : Natural;
                  Extra_Offset : Natural := File_Header_Payload_Size;
                  Data_Offset  : constant Natural := Header_Start + Header_Size;
               begin
                  if Body_Size < File_Header_Payload_Size then
                     Fail (Invalid_Header);
                     return;
                  end if;

                  declare
                     Header_Body : Ada.Streams.Stream_Element_Array
                       (1 .. Ada.Streams.Stream_Element_Offset (Body_Size));
                  begin
                     if not Read_Exact (File, Body_Size, Header_Body) then
                        Fail (Input_File_Error);
                        return;
                     end if;

                     Pack_Low   := U32_LE (Header_Body, 0);
                     Unpack_Low := U32_LE (Header_Body, 4);
                     File_CRC   := U32_LE (Header_Body, 9);
                     Method     := Byte_At (Header_Body, 18);
                     Name_Size  := U16_LE (Header_Body, 19);

                     if (Flags and Flag_Large) /= No_Flags then
                        if Body_Size < File_Header_Payload_Size + 8 then
                           Fail (Invalid_Header);
                           return;
                        end if;
                        Pack_Size :=
                          U64_From_High_Low
                            (U32_LE (Header_Body, 25), Pack_Low);
                        Unpack_Size :=
                          U64_From_High_Low
                            (U32_LE (Header_Body, 29), Unpack_Low);
                        Extra_Offset := Extra_Offset + 8;
                     else
                        Pack_Size   := Pack_Low;
                        Unpack_Size := Unpack_Low;
                     end if;

                     if Name_Size = 0
                       or else Name_Size > Body_Size - Extra_Offset
                       or else Pack_Size > Interfaces.Unsigned_64 (Natural'Last)
                       or else
                         Unpack_Size > Interfaces.Unsigned_64 (Natural'Last)
                       or else
                         Natural (Pack_Size) > Natural (Size) - Data_Offset
                     then
                        Fail (Invalid_Header);
                        return;
                     end if;

                     declare
                        Name      : constant String :=
                          Bytes_To_String
                            (Header_Body,
                             Header_Body'First
                               + Ada.Streams.Stream_Element_Offset
                                   (Extra_Offset),
                             Name_Size);
                        Stored    : constant Boolean := Method = Method_Store;
                        Is_Dir    : constant Boolean :=
                          (Flags and Flag_Directory) = Flag_Directory;
                        Encrypted : constant Boolean :=
                          (Flags and Flag_Encrypted) /= No_Flags;
                        Meta      : constant String :=
                          "rar.version=4;rar.method=0x" & Hex2 (Method)
                          & ";rar.header_offset="
                          & U64_Image (Interfaces.Unsigned_64 (Header_Start))
                          & (if Encrypted then ";rar.encrypted=1" else "");
                     begin
                        Members.Append
                          (Member'(Name        => To_Unbounded_String (Name),
                                   Data_Offset => Data_Offset,
                                   Payload     => Natural (Unpack_Size),
                                   Streamable  =>
                                     not Is_Dir and then Stored
                                     and then not Encrypted,
                                   CRC         =>
                                     Interfaces.Unsigned_32 (File_CRC),
                                   Meta        => To_Unbounded_String (Meta),
                                   Compression =>
                                     (if Stored then 0
                                      else Interfaces.Unsigned_16 (Method))));
                     end;
                  end;

                  Offset := Data_Offset + Natural (Pack_Size);
               end;
            else
               if Add_Size > Interfaces.Unsigned_64 (Natural'Last)
                 or else
                   Natural (Add_Size) > Natural (Size) - (Offset + Header_Size)
               then
                  Fail (Invalid_Header);
                  return;
               end if;
               Offset := Offset + Header_Size + Natural (Add_Size);
            end if;
         end;
      end loop;

      Ada.Streams.Stream_IO.Close (File);
      if not Saw_End then
         Members := Member_Vectors.Empty_Vector;
         Status := Invalid_Header;   --  no End_Of_Archive block
      else
         Status := Ok;
      end if;
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
            Result (Index).Is_Directory := False;
            Result (Index).Compression := M.Compression;
            Result (Index).Uncompressed_Size :=
              Interfaces.Unsigned_64 (M.Payload);
            Result (Index).Compressed_Size :=
              Interfaces.Unsigned_64 (M.Payload);
            Result (Index).CRC_32 := M.CRC;
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
      Expected    : Interfaces.Unsigned_32 := 0;
      CRC         : CryptoLib.Checksums.CRC32_State;
      File        : Ada.Streams.Stream_IO.File_Type;
   begin
      Index_Members (Archive_Path, Members, Status);
      if Status /= Ok then
         return;
      end if;

      for M of Members loop
         if To_String (M.Name) = Entry_Name then
            Found       := True;
            Streamable  := M.Streamable;
            Data_Offset := M.Data_Offset;
            Remaining   := M.Payload;
            Expected    := M.CRC;
            exit;
         end if;
      end loop;

      if not Found then
         Status := Invalid_Header;   --  no such member
         return;
      elsif not Streamable then
         Status := Unsupported_Method;   --  compressed, encrypted, or directory
         return;
      end if;

      CryptoLib.Checksums.CRC32_Reset (CRC);
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

            CryptoLib.Checksums.CRC32_Update (CRC, Raw (Raw'First .. Last));

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
      if CryptoLib.Checksums.CRC32_Value (CRC) /= Expected then
         Status := Invalid_Checksum;
      else
         Status := Ok;
      end if;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Status := Input_File_Error;
   end Extract_Entry;

end Zlib.Rar_Reader;
