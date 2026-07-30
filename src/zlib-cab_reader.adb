with Ada.Strings.Unbounded;
with Interfaces; use type Interfaces.Unsigned_32;

package body Zlib.Cab_Reader is

   package US renames Ada.Strings.Unbounded;

   Header_Size            : constant Natural := 36;
   Folder_Size            : constant Natural := 8;
   File_Record_Fixed_Size : constant Natural := 16;
   Data_Block_Header_Size : constant Natural := 8;
   Max_Name_Length        : constant Natural := 4_096;

   Empty_Bytes   : constant Byte_Array (1 .. 0) := [others => 0];
   Default_Entry : constant Archive_Entry := (others => <>);
   No_Entries    : constant Archive_Entry_Array (1 .. 0) := [others => Default_Entry];

   --  Little-endian field reads, relative to Image'First. The caller guarantees
   --  the bytes are in range before reading.
   function U16 (Image : Byte_Array; Off : Natural) return Natural is
     (Natural (Image (Image'First + Off))
      + Natural (Image (Image'First + Off + 1)) * 256);

   function U32 (Image : Byte_Array; Off : Natural) return Interfaces.Unsigned_32 is
     (Interfaces.Unsigned_32 (Image (Image'First + Off))
      + Interfaces.Shift_Left (Interfaces.Unsigned_32 (Image (Image'First + Off + 1)), 8)
      + Interfaces.Shift_Left (Interfaces.Unsigned_32 (Image (Image'First + Off + 2)), 16)
      + Interfaces.Shift_Left (Interfaces.Unsigned_32 (Image (Image'First + Off + 3)), 24));

   type Cab_Info is record
      Ok                 : Boolean := False;
      Status             : Status_Code := Invalid_Header;
      File_Count         : Natural := 0;
      Files_Offset       : Natural := 0;   --  offset of the first CFFILE
      Payload_Offset     : Natural := 0;   --  offset of the CFDATA payload
      Compression        : Natural := 0;   --  0 = Store, 1 = MSZIP
      Block_Compressed   : Natural := 0;
      Block_Uncompressed : Natural := 0;
   end record;

   type File_Record is record
      Ok           : Boolean := False;
      Name         : US.Unbounded_String := US.Null_Unbounded_String;
      Size         : Natural := 0;
      Offset       : Natural := 0;         --  offset within the folder payload
      Folder_Index : Natural := 0;
      Is_Directory : Boolean := False;
      Next         : Natural := 0;         --  offset just past this record
   end record;

   --  Parse and validate the fixed cabinet structure (single folder, single
   --  CFDATA block, Store or MSZIP, no reserved fields), leaving the file table
   --  to the callers. Fails closed on anything else.
   function Parse (Image : Byte_Array) return Cab_Info is
      Len  : constant Natural := Image'Length;
      Info : Cab_Info;
   begin
      if Len < Header_Size + Folder_Size then
         Info.Status := Unexpected_End_Of_Input;
         return Info;
      end if;

      if Image (Image'First) /= 16#4D#           --  'M'
        or else Image (Image'First + 1) /= 16#53#  --  'S'
        or else Image (Image'First + 2) /= 16#43#  --  'C'
        or else Image (Image'First + 3) /= 16#46#  --  'F'
      then
         Info.Status := Invalid_Header;
         return Info;
      end if;

      declare
         Cabinet_Size : constant Interfaces.Unsigned_32 := U32 (Image, 8);
         Files_Off    : constant Interfaces.Unsigned_32 := U32 (Image, 16);
         Folder_Count : constant Natural := U16 (Image, 26);
         File_Count   : constant Natural := U16 (Image, 28);
         Flags        : constant Natural := U16 (Image, 30);
      begin
         if Cabinet_Size = 0
           or else Cabinet_Size > Interfaces.Unsigned_32 (Len)
           or else Folder_Count /= 1
           or else File_Count = 0
           or else Flags /= 0
           or else Files_Off > Interfaces.Unsigned_32 (Len)
         then
            Info.Status := Unsupported_Method;
            return Info;
         end if;

         Info.File_Count := File_Count;
         Info.Files_Offset := Natural (Files_Off);
         if Info.Files_Offset < Header_Size + Folder_Size then
            Info.Status := Invalid_Header;
            return Info;
         end if;
      end;

      --  The single CFFOLDER sits right after the fixed header (Flags = 0 means
      --  no reserved fields).
      declare
         Data_Off    : constant Interfaces.Unsigned_32 := U32 (Image, Header_Size);
         Block_Count : constant Natural := U16 (Image, Header_Size + 4);
         Compression : constant Natural := U16 (Image, Header_Size + 6);
         Data_Offset : Natural;
      begin
         if (Compression /= 0 and then Compression /= 1)
           or else Block_Count /= 1
           or else Data_Off > Interfaces.Unsigned_32 (Len)
         then
            Info.Status := Unsupported_Method;
            return Info;
         end if;

         Data_Offset := Natural (Data_Off);
         if Data_Offset + Data_Block_Header_Size > Len then
            Info.Status := Unexpected_End_Of_Input;
            return Info;
         end if;

         Info.Compression := Compression;
         Info.Block_Compressed := U16 (Image, Data_Offset + 4);
         Info.Block_Uncompressed := U16 (Image, Data_Offset + 6);
         Info.Payload_Offset := Data_Offset + Data_Block_Header_Size;

         if Info.Payload_Offset > Len
           or else Info.Block_Compressed > Len - Info.Payload_Offset
           or else (Compression = 0
                    and then Info.Block_Compressed /= Info.Block_Uncompressed)
           or else (Compression = 1 and then Info.Block_Compressed <= 2)
         then
            Info.Status := Invalid_Header;
            return Info;
         end if;
      end;

      Info.Ok := True;
      Info.Status := Ok;
      return Info;
   end Parse;

   --  Read one CFFILE (16 fixed bytes + a NUL-terminated Latin-1 name) at Pos.
   function Read_File_Record (Image : Byte_Array; Pos : Natural) return File_Record is
      Len : constant Natural := Image'Length;
      Rec : File_Record;
   begin
      if Pos > Len or else Pos + File_Record_Fixed_Size > Len then
         return Rec;   --  Ok is False
      end if;

      declare
         Sz  : constant Interfaces.Unsigned_32 := U32 (Image, Pos);
         Ofs : constant Interfaces.Unsigned_32 := U32 (Image, Pos + 4);
      begin
         if Sz > Interfaces.Unsigned_32 (Len)
           or else Ofs > Interfaces.Unsigned_32 (Len)
         then
            return Rec;
         end if;
         Rec.Size := Natural (Sz);
         Rec.Offset := Natural (Ofs);
      end;

      Rec.Folder_Index := U16 (Image, Pos + 8);
      Rec.Is_Directory := (U16 (Image, Pos + 14) / 16) mod 2 = 1;

      --  NUL-terminated name.
      declare
         Name_Start : constant Natural := Pos + File_Record_Fixed_Size;
         Name_End   : Natural := Name_Start;
      begin
         while Name_End < Len
           and then Name_End - Name_Start < Max_Name_Length
           and then Image (Image'First + Name_End) /= 0
         loop
            Name_End := Name_End + 1;
         end loop;

         if Name_End >= Len
           or else Image (Image'First + Name_End) /= 0
           or else Name_End = Name_Start
         then
            return Rec;   --  no terminator, too long, or empty name
         end if;

         declare
            Text : String (1 .. Name_End - Name_Start);
         begin
            for I in Text'Range loop
               Text (I) := Character'Val
                 (Natural (Image (Image'First + Name_Start + I - 1)));
            end loop;
            Rec.Name := US.To_Unbounded_String (Text);
         end;
         Rec.Next := Name_End + 1;   --  past the NUL
      end;

      Rec.Ok := True;
      return Rec;
   end Read_File_Record;

   --  True when Rec is a valid member of the folder described by Info.
   function Valid_File (Rec : File_Record; Info : Cab_Info) return Boolean is
     (Rec.Ok
      and then Rec.Folder_Index = 0
      and then Rec.Offset <= Info.Block_Uncompressed
      and then Rec.Size <= Info.Block_Uncompressed - Rec.Offset
      and then (not Rec.Is_Directory or else Rec.Size = 0));

   --  Decode the single folder's whole payload: a Store block is the payload
   --  bytes verbatim; an MSZIP block is raw Deflate behind a 'CK' signature.
   function Decode_Folder
     (Image  : Byte_Array;
      Info   : Cab_Info;
      Status : out Status_Code) return Byte_Array
   is
      Base : constant Natural := Image'First;
   begin
      if Info.Compression = 0 then
         Status := Ok;
         return Image (Base + Info.Payload_Offset ..
                       Base + Info.Payload_Offset + Info.Block_Uncompressed - 1);
      end if;

      --  MSZIP: two-byte 'CK' signature then a raw Deflate stream.
      if Image (Base + Info.Payload_Offset) /= 16#43#          --  'C'
        or else Image (Base + Info.Payload_Offset + 1) /= 16#4B#  --  'K'
      then
         Status := Invalid_Header;
         return Empty_Bytes;
      end if;

      declare
         Inflated : constant Byte_Array :=
           Inflate_Raw
             (Image (Base + Info.Payload_Offset + 2 ..
                     Base + Info.Payload_Offset + Info.Block_Compressed - 1),
              Status);
      begin
         if Status /= Ok then
            return Empty_Bytes;
         end if;
         if Inflated'Length /= Info.Block_Uncompressed then
            Status := Invalid_Checksum;
            return Empty_Bytes;
         end if;
         Status := Ok;
         return Inflated;
      end;
   end Decode_Folder;

   function List_Entries
     (Archive_Image : Byte_Array;
      Status        : out Status_Code) return Archive_Entry_Array
   is
      Info : constant Cab_Info := Parse (Archive_Image);
   begin
      if not Info.Ok then
         Status := Info.Status;
         return No_Entries;
      end if;

      declare
         Result : Archive_Entry_Array (1 .. Info.File_Count);
         Pos    : Natural := Info.Files_Offset;
      begin
         for I in 1 .. Info.File_Count loop
            declare
               Rec : constant File_Record := Read_File_Record (Archive_Image, Pos);
            begin
               if not Valid_File (Rec, Info) then
                  Status := Invalid_Header;
                  return No_Entries;
               end if;
               Result (I).Name := Rec.Name;
               Result (I).Is_Directory := Rec.Is_Directory;
               Result (I).Compression :=
                 (if Info.Compression = 1 then 8 else 0);
               Result (I).Uncompressed_Size := Interfaces.Unsigned_64 (Rec.Size);
               Result (I).Compressed_Size :=
                 Interfaces.Unsigned_64
                   (if Info.Compression = 1 then Info.Block_Compressed else Rec.Size);
               Result (I).CRC_32 := 0;
               Pos := Rec.Next;
            end;
         end loop;

         Status := Ok;
         return Result;
      end;
   end List_Entries;

   function Extract_Entry
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Byte_Array
   is
      Info     : constant Cab_Info := Parse (Archive_Image);
      Pos      : Natural;
      Found    : Boolean := False;
      F_Offset : Natural := 0;
      F_Size   : Natural := 0;
      F_Is_Dir : Boolean := False;
   begin
      if not Info.Ok then
         Status := Info.Status;
         return Empty_Bytes;
      end if;

      Pos := Info.Files_Offset;
      for I in 1 .. Info.File_Count loop
         declare
            Rec : constant File_Record := Read_File_Record (Archive_Image, Pos);
         begin
            if not Valid_File (Rec, Info) then
               Status := Invalid_Header;
               return Empty_Bytes;
            end if;
            if US.To_String (Rec.Name) = Entry_Name then
               Found := True;
               F_Offset := Rec.Offset;
               F_Size := Rec.Size;
               F_Is_Dir := Rec.Is_Directory;
               exit;
            end if;
            Pos := Rec.Next;
         end;
      end loop;

      if not Found then
         Status := Invalid_Header;   --  no such entry
         return Empty_Bytes;
      end if;

      if F_Is_Dir then
         Status := Ok;
         return Empty_Bytes;
      end if;

      declare
         Folder : constant Byte_Array := Decode_Folder (Archive_Image, Info, Status);
      begin
         if Status /= Ok then
            return Empty_Bytes;
         end if;
         return Folder (Folder'First + F_Offset ..
                        Folder'First + F_Offset + F_Size - 1);
      end;
   end Extract_Entry;

end Zlib.Cab_Reader;
