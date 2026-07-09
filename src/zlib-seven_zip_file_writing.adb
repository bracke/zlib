with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Unbounded;
with CryptoLib.Checksums;
with Interfaces;
with Zlib.Seven_Zip_AES;
with Zlib.Seven_Zip_Codec_Packing;
with Zlib.Seven_Zip_Codec_Writing;
with Zlib.Seven_Zip_Container;
with Zlib.Seven_Zip_Paths;
with Zlib.Seven_Zip_Properties;

package body Zlib.Seven_Zip_File_Writing is

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Byte);

   function To_Byte_Array (Data : Byte_Vectors.Vector) return Byte_Array
   is
      Output : Byte_Array (1 .. Natural (Data.Length));
      Pos    : Natural := Output'First;
   begin
      for B of Data loop
         Output (Pos) := B;
         Pos := Pos + 1;
      end loop;

      return Output;
   end To_Byte_Array;

   function Compute_CRC32 (Data : Byte_Array) return Interfaces.Unsigned_32 is
      State : CryptoLib.Checksums.CRC32_State;
   begin
      CryptoLib.Checksums.CRC32_Reset (State);
      for B of Data loop
         CryptoLib.Checksums.CRC32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.CRC32_Value (State);
   end Compute_CRC32;

   procedure Write_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Build_Archive   : not null access function
        (Input      : Byte_Array;
         Entry_Name : String;
         Metadata   : Seven_Zip_Entry_Metadata;
         Status     : out Status_Code) return Byte_Array;
      Status          : out Status_Code)
   is
      Empty        : constant Byte_Array (1 .. 0) := [others => 0];
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;

      if not Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name) then
         return;
      end if;

      if not Zlib.Seven_Zip_Paths.Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;

      if not Zlib.Seven_Zip_Paths.Input_Path_Readable (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      declare
         Metadata : constant Seven_Zip_Entry_Metadata :=
           Source_Metadata (Input_Path);
      begin
         if Metadata.Is_Directory then
            declare
               Archive : constant Byte_Array :=
                 Build_Archive (Empty, Entry_Name, Metadata, Status);
            begin
               if Status /= Ok then
                  return;
               end if;

               Write_File (Output_Path, Archive, Write_Status);
               Status := Write_Status;
            end;
         else
            declare
               Input_Data : constant Byte_Array :=
                 Read_File (Input_Path, Read_Status);
            begin
               if Read_Status /= Ok then
                  Status := Read_Status;
                  return;
               end if;

               declare
                  Archive : constant Byte_Array :=
                    Build_Archive (Input_Data, Entry_Name, Metadata, Status);
               begin
                  if Status /= Ok then
                     return;
                  end if;

                  Write_File (Output_Path, Archive, Write_Status);
                  Status := Write_Status;
               end;
            end;
         end if;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Write_File_Archive;

   procedure Write_Stored_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Status          : out Status_Code)
   is
      function Build_Stored
        (Input      : Byte_Array;
         Entry_Name : String;
         Metadata   : Seven_Zip_Entry_Metadata;
         Status     : out Status_Code) return Byte_Array is
      begin
         return
           Zlib.Seven_Zip_Codec_Writing.Build_Copy
             (Input, Entry_Name, Metadata, Status);
      end Build_Stored;
   begin
      Write_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File, Write_File,
         Source_Metadata, Build_Stored'Access, Status);
   end Write_Stored_File_Archive;

   procedure Write_PPMd_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Status          : out Status_Code)
   is
      function Build_PPMd
        (Input      : Byte_Array;
         Entry_Name : String;
         Metadata   : Seven_Zip_Entry_Metadata;
         Status     : out Status_Code) return Byte_Array is
      begin
         return
           Zlib.Seven_Zip_Codec_Writing.Build_PPMd
             (Input, Entry_Name, Metadata, Status);
      end Build_PPMd;
   begin
      Write_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File, Write_File,
         Source_Metadata, Build_PPMd'Access, Status);
   end Write_PPMd_File_Archive;

   procedure Write_PPMd_File_With_Basename
     (Input_Path      : String;
      Output_Path     : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Status          : out Status_Code)
   is
   begin
      Status := Unsupported_Method;

      if not Zlib.Seven_Zip_Paths.Output_File_Writable (Output_Path) then
         Status := Output_File_Error;
         return;
      end if;

      if not Zlib.Seven_Zip_Paths.Input_Path_Readable (Input_Path) then
         Status := Input_File_Error;
         return;
      end if;

      Write_PPMd_File_Archive
        (Input_Path, Output_Path, Ada.Directories.Simple_Name (Input_Path),
         Read_File, Write_File, Source_Metadata, Status);
   exception
      when others =>
         Status := Input_File_Error;
   end Write_PPMd_File_With_Basename;

   procedure Write_Deflate_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Compress        : not null access function
        (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
      Status          : out Status_Code)
   is
      function Build_Deflate
        (Input      : Byte_Array;
         Entry_Name : String;
         Metadata   : Seven_Zip_Entry_Metadata;
         Status     : out Status_Code) return Byte_Array is
      begin
         return
           Zlib.Seven_Zip_Codec_Writing.Build_Deflate
             (Input, Entry_Name, Metadata, Compress, Status);
      end Build_Deflate;
   begin
      Write_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File, Write_File,
         Source_Metadata, Build_Deflate'Access, Status);
   end Write_Deflate_File_Archive;

   procedure Write_BZip2_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Compress        : not null access function
        (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
      Status          : out Status_Code)
   is
      function Build_BZip2
        (Input      : Byte_Array;
         Entry_Name : String;
         Metadata   : Seven_Zip_Entry_Metadata;
         Status     : out Status_Code) return Byte_Array is
      begin
         return
           Zlib.Seven_Zip_Codec_Writing.Build_BZip2
             (Input, Entry_Name, Metadata, Compress, Status);
      end Build_BZip2;
   begin
      Write_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File, Write_File,
         Source_Metadata, Build_BZip2'Access, Status);
   end Write_BZip2_File_Archive;

   procedure Write_LZMA_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Encode          : not null access function
        (Input : Byte_Array; LZMA_Props : in out Byte) return Byte_Array;
      Status          : out Status_Code)
   is
      function Build_LZMA
        (Input      : Byte_Array;
         Entry_Name : String;
         Metadata   : Seven_Zip_Entry_Metadata;
         Status     : out Status_Code) return Byte_Array is
      begin
         return
           Zlib.Seven_Zip_Codec_Writing.Build_LZMA
             (Input, Entry_Name, Metadata, Encode, Status);
      end Build_LZMA;
   begin
      Write_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File, Write_File,
         Source_Metadata, Build_LZMA'Access, Status);
   end Write_LZMA_File_Archive;

   procedure Write_LZMA2_File_Archive
     (Input_Path      : String;
      Output_Path     : String;
      Entry_Name      : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Encode          : not null access function
        (Input : Byte_Array) return Byte_Array;
      Status          : out Status_Code)
   is
      function Build_LZMA2
        (Input      : Byte_Array;
         Entry_Name : String;
         Metadata   : Seven_Zip_Entry_Metadata;
         Status     : out Status_Code) return Byte_Array is
      begin
         return
           Zlib.Seven_Zip_Codec_Writing.Build_LZMA2
             (Input, Entry_Name, Metadata, Encode, Status);
      end Build_LZMA2;
   begin
      Write_File_Archive
        (Input_Path, Output_Path, Entry_Name, Read_File, Write_File,
         Source_Metadata, Build_LZMA2'Access, Status);
   end Write_LZMA2_File_Archive;

   procedure Write_Stored_File_List
     (Input_Paths     : Text_Array;
      Output_Path     : String;
      Entry_Names     : Text_Array;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Status          : out Status_Code)
   is
      Count        : constant Natural := Input_Paths'Length;
      Payloads     : Byte_Vectors.Vector;
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
   begin
      Status := Unsupported_Method;

      if Count = 0 or else Entry_Names'Length /= Count then
         return;
      end if;

      declare
         Sizes              : Zlib.Seven_Zip_Container.U64_Array (1 .. Count) :=
           [others => 0];
         CRCs               : Zlib.Seven_Zip_Container.U32_Array (1 .. Count) :=
           [others => 0];
         Metadata           : Zlib.Seven_Zip_Properties.Entry_Metadata_Array
           (1 .. Count) := [others => No_Seven_Zip_Entry_Metadata];
         Entry_Is_Directory : Zlib.Seven_Zip_Container.Boolean_Array
           (1 .. Count) := [others => False];
         Stream_Count       : Natural := 0;
      begin
         if not Zlib.Seven_Zip_Paths.Entry_Names_Valid (Entry_Names) then
            return;
         end if;

         if not Zlib.Seven_Zip_Paths.Output_File_Writable (Output_Path) then
            Status := Output_File_Error;
            return;
         end if;

         if not Zlib.Seven_Zip_Paths.Input_Paths_Readable (Input_Paths) then
            Status := Input_File_Error;
            return;
         end if;

         for Offset in 0 .. Count - 1 loop
            declare
               Input_Path : constant String :=
                 Ada.Strings.Unbounded.To_String
                   (Input_Paths (Input_Paths'First + Offset));
            begin
               Metadata (Offset + 1) := Source_Metadata (Input_Path);
               Entry_Is_Directory (Offset + 1) :=
                 Metadata (Offset + 1).Is_Directory;

               if not Entry_Is_Directory (Offset + 1) then
                  Stream_Count := Stream_Count + 1;
                  declare
                     Input_Data : constant Byte_Array :=
                       Read_File (Input_Path, Read_Status);
                  begin
                     if Read_Status /= Ok then
                        Status := Read_Status;
                        return;
                     end if;

                     Sizes (Stream_Count) :=
                       Interfaces.Unsigned_64 (Input_Data'Length);
                     CRCs (Stream_Count) := Compute_CRC32 (Input_Data);
                     for B of Input_Data loop
                        Payloads.Append (B);
                     end loop;
                  end;
               end if;
            end;
         end loop;

         declare
            Payload_Image : constant Byte_Array := To_Byte_Array (Payloads);
            Archive       : constant Byte_Array :=
              Zlib.Seven_Zip_Container.Stored_File_List_Archive
                (Payload_Image, Entry_Names, Sizes, CRCs, Metadata,
                 Entry_Is_Directory, Stream_Count, Status);
         begin
            if Status /= Ok then
               return;
            end if;

            Write_File (Output_Path, Archive, Write_Status);
            Status := Write_Status;
         end;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Write_Stored_File_List;

   procedure Write_Compressed_File_List
     (Input_Paths     : Text_Array;
      Output_Path     : String;
      Entry_Names     : Text_Array;
      Method          : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Solid           : Boolean;
      Password        : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Pack_Input      : not null access function
        (Input_Data  : Byte_Array;
         LZMA_Props  : in out Byte;
         Pack_Status : out Status_Code) return Byte_Array;
      Status          : out Status_Code)
   is
      Count                : constant Natural := Input_Paths'Length;
      Payloads             : Byte_Vectors.Vector;
      Solid_Input          : Byte_Vectors.Vector;
      Read_Status          : Status_Code := Ok;
      Write_Status         : Status_Code := Ok;
      Encrypt              : constant Boolean := Password /= "";
      Solid_Compressed_Len : Natural := 0;
      AES_IV               : Byte_Array (1 .. 16) := [others => 0];
      Default_LZMA_Props   : constant Byte := 16#5D#;
   begin
      Status := Unsupported_Method;

      if Count = 0 or else Entry_Names'Length /= Count then
         return;
      end if;

      declare
         Pack_Sizes         : Zlib.Seven_Zip_Container.U64_Array (1 .. Count) :=
           [others => 0];
         Pack_CRCs          : Zlib.Seven_Zip_Container.U32_Array (1 .. Count) :=
           [others => 0];
         Unpack_Sizes       : Zlib.Seven_Zip_Container.U64_Array (1 .. Count) :=
           [others => 0];
         Unpack_CRCs        : Zlib.Seven_Zip_Container.U32_Array (1 .. Count) :=
           [others => 0];
         LZMA_Props         : Byte_Array (1 .. Count) :=
           [others => Default_LZMA_Props];
         Metadata           : Zlib.Seven_Zip_Properties.Entry_Metadata_Array
           (1 .. Count) := [others => No_Seven_Zip_Entry_Metadata];
         Entry_Is_Directory : Zlib.Seven_Zip_Container.Boolean_Array
           (1 .. Count) := [others => False];
         Stream_Count       : Natural := 0;
      begin
         if not Zlib.Seven_Zip_Paths.Entry_Names_Valid (Entry_Names) then
            return;
         end if;

         if not Zlib.Seven_Zip_Paths.Output_File_Writable (Output_Path) then
            Status := Output_File_Error;
            return;
         end if;

         if not Zlib.Seven_Zip_Paths.Input_Paths_Readable (Input_Paths) then
            Status := Input_File_Error;
            return;
         end if;

         for Offset in 0 .. Count - 1 loop
            declare
               Input_Path : constant String :=
                 Ada.Strings.Unbounded.To_String
                   (Input_Paths (Input_Paths'First + Offset));
            begin
               Metadata (Offset + 1) := Source_Metadata (Input_Path);
               Entry_Is_Directory (Offset + 1) :=
                 Metadata (Offset + 1).Is_Directory;

               if not Entry_Is_Directory (Offset + 1) then
                  Stream_Count := Stream_Count + 1;
                  declare
                     Input_Data : constant Byte_Array :=
                       Read_File (Input_Path, Read_Status);
                  begin
                     if Read_Status /= Ok then
                        Status := Read_Status;
                        return;
                     end if;

                     Unpack_Sizes (Stream_Count) :=
                       Interfaces.Unsigned_64 (Input_Data'Length);
                     Unpack_CRCs (Stream_Count) := Compute_CRC32 (Input_Data);

                     if Solid then
                        for B of Input_Data loop
                           Solid_Input.Append (B);
                        end loop;
                     else
                        declare
                           Compress_Status : Status_Code := Ok;
                           Stream_Props    : Byte := Default_LZMA_Props;
                           Packed_Data     : constant Byte_Array :=
                             Pack_Input
                               (Input_Data, Stream_Props, Compress_Status);
                        begin
                           if Compress_Status /= Ok then
                              Status := Compress_Status;
                              return;
                           end if;

                           LZMA_Props (Stream_Count) := Stream_Props;
                           Pack_Sizes (Stream_Count) :=
                             Interfaces.Unsigned_64 (Packed_Data'Length);
                           Pack_CRCs (Stream_Count) :=
                             Compute_CRC32 (Packed_Data);

                           for B of Packed_Data loop
                              Payloads.Append (B);
                           end loop;
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;

         if Solid and then Stream_Count > 0 then
            declare
               Solid_Data      : constant Byte_Array :=
                 To_Byte_Array (Solid_Input);
               Compress_Status : Status_Code := Ok;
               Stream_Props    : Byte := Default_LZMA_Props;
               Packed_Data     : constant Byte_Array :=
                 Pack_Input (Solid_Data, Stream_Props, Compress_Status);
            begin
               if Compress_Status /= Ok then
                  Status := Compress_Status;
                  return;
               end if;

               LZMA_Props (1) := Stream_Props;
               Solid_Compressed_Len := Packed_Data'Length;

               if Encrypt then
                  AES_IV := Zlib.Seven_Zip_AES.Random_IV;
                  declare
                     Pack : constant Byte_Array :=
                       Zlib.Seven_Zip_AES.Encrypt_CBC
                         (Zlib.Seven_Zip_AES.Derive_Key
                            (Password, [1 .. 0 => 0], 19),
                          AES_IV,
                          Zlib.Seven_Zip_AES.Pad_To_Block (Packed_Data));
                  begin
                     Pack_Sizes (1) := Interfaces.Unsigned_64 (Pack'Length);
                     for B of Pack loop
                        Payloads.Append (B);
                     end loop;
                  end;
               else
                  Pack_Sizes (1) :=
                    Interfaces.Unsigned_64 (Packed_Data'Length);
                  for B of Packed_Data loop
                     Payloads.Append (B);
                  end loop;
               end if;
            end;
         end if;

         declare
            Payload_Image : constant Byte_Array := To_Byte_Array (Payloads);
            Archive       : constant Byte_Array :=
              Zlib.Seven_Zip_Container.Compressed_File_List_Archive
                (Payload_Image, Entry_Names, Method, Pack_Sizes, Pack_CRCs,
                 Unpack_Sizes, Unpack_CRCs, LZMA_Props, Metadata,
                 Entry_Is_Directory, Stream_Count, Solid, Encrypt,
                 Solid_Compressed_Len, AES_IV, Status);
         begin
            if Status /= Ok then
               return;
            end if;

            Write_File (Output_Path, Archive, Write_Status);
            Status := Write_Status;
         end;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Write_Compressed_File_List;

   procedure Write_Compressed_File_List_Selected
     (Input_Paths     : Text_Array;
      Output_Path     : String;
      Entry_Names     : Text_Array;
      Method          : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Mode            : Compression_Mode;
      Level           : Compression_Level;
      Use_Level       : Boolean;
      Solid           : Boolean;
      Password        : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File      : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Source_Metadata : not null access function
        (Path : String) return Seven_Zip_Entry_Metadata;
      Deflate_Mode    : not null access function
        (Input  : Byte_Array;
         Mode   : Compression_Mode;
         Status : out Status_Code) return Byte_Array;
      Deflate_Level   : not null access function
        (Input  : Byte_Array;
         Level  : Compression_Level;
         Status : out Status_Code) return Byte_Array;
      BZip2           : not null access function
        (Input : Byte_Array; Status : out Status_Code) return Byte_Array;
      LZMA            : not null access function
        (Input : Byte_Array; LZMA_Props : in out Byte) return Byte_Array;
      LZMA2           : not null access function
        (Input : Byte_Array) return Byte_Array;
      Default_Props   : Byte;
      Status          : out Status_Code)
   is
      function Pack_Input
        (Input_Data  : Byte_Array;
         LZMA_Props  : in out Byte;
         Pack_Status : out Status_Code) return Byte_Array
      is
         function Pack_Deflate
           (Input  : Byte_Array;
            Status : out Status_Code) return Byte_Array is
         begin
            if Use_Level then
               return Deflate_Level (Input, Level, Status);
            else
               return Deflate_Mode (Input, Mode, Status);
            end if;
         end Pack_Deflate;
      begin
         return
           Zlib.Seven_Zip_Codec_Packing.Pack_Method
             (Input_Data, Method, Default_Props, Pack_Deflate'Access,
              BZip2, LZMA, LZMA2, LZMA_Props, Pack_Status);
      end Pack_Input;
   begin
      Write_Compressed_File_List
        (Input_Paths, Output_Path, Entry_Names, Method, Solid, Password,
         Read_File, Write_File, Source_Metadata, Pack_Input'Access, Status);
   end Write_Compressed_File_List_Selected;

end Zlib.Seven_Zip_File_Writing;
