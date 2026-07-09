with Ada.Directories;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Zlib.Seven_Zip_Paths;
with Zlib.Seven_Zip_Properties;

package body Zlib.Seven_Zip_File_Extraction is

   use type Ada.Directories.File_Kind;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Byte);
   package US renames Ada.Strings.Unbounded;

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

   function Extract_Metadata
     (Archive_Image  : Byte_Array;
      Entry_Name     : String;
      Extract_Entry  : not null access function
        (Archive      : Byte_Array;
         Entry_Name   : String;
         Status       : out Status_Code;
         Is_Directory : out Boolean;
         Metadata     : out Seven_Zip_Entry_Metadata) return Byte_Array;
      Status         : out Status_Code) return Seven_Zip_Entry_Metadata
   is
      Is_Directory : Boolean := False;
      Metadata     : Seven_Zip_Entry_Metadata := No_Seven_Zip_Entry_Metadata;
      Payload      : constant Byte_Array :=
        Extract_Entry (Archive_Image, Entry_Name, Status, Is_Directory, Metadata);
      pragma Unreferenced (Payload);
   begin
      if Status /= Ok then
         return No_Seven_Zip_Entry_Metadata;
      end if;

      Metadata.Is_Directory := Is_Directory;
      return Metadata;
   exception
      when others =>
         Status := Unsupported_Method;
         return No_Seven_Zip_Entry_Metadata;
   end Extract_Metadata;

   procedure Extract_File
     (Input_Path    : String;
      Output_Path   : String;
      Entry_Name    : String;
      Read_File     : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File    : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Extract_Entry : not null access function
        (Archive      : Byte_Array;
         Entry_Name   : String;
         Status       : out Status_Code;
         Is_Directory : out Boolean;
         Metadata     : out Seven_Zip_Entry_Metadata) return Byte_Array;
      Status        : out Status_Code)
   is
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

      declare
         Archive : constant Byte_Array := Read_File (Input_Path, Read_Status);
      begin
         if Read_Status /= Ok then
            Status := Read_Status;
            return;
         end if;

         declare
            Is_Directory : Boolean := False;
            Metadata     : Seven_Zip_Entry_Metadata;
            Payload      : constant Byte_Array :=
              Extract_Entry (Archive, Entry_Name, Status, Is_Directory, Metadata);
         begin
            if Status /= Ok then
               return;
            end if;

            if Is_Directory then
               begin
                  Ada.Directories.Create_Path
                    (Ada.Directories.Containing_Directory (Output_Path));
                  Ada.Directories.Create_Path (Output_Path);
               exception
                  when others =>
                     Status := Output_File_Error;
                     return;
               end;

               Zlib.Seven_Zip_Properties.Apply_Metadata (Output_Path, Metadata);
               Status := Ok;
               return;
            end if;

            begin
               Ada.Directories.Create_Path
                 (Ada.Directories.Containing_Directory (Output_Path));
            exception
               when others =>
                  Status := Output_File_Error;
                  return;
            end;

            Write_File (Output_Path, Payload, Write_Status);
            if Write_Status /= Ok then
               Status := Write_Status;
               return;
            end if;

            Zlib.Seven_Zip_Properties.Apply_Metadata (Output_Path, Metadata);
            Status := Ok;
         end;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Extract_File;

   procedure Extract_Files
     (Input_Path    : String;
      Output_Dir    : String;
      Entry_Names   : Text_Array;
      Read_File     : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Write_File    : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Extract_Entry : not null access function
        (Archive      : Byte_Array;
         Entry_Name   : String;
         Status       : out Status_Code;
         Is_Directory : out Boolean;
         Metadata     : out Seven_Zip_Entry_Metadata) return Byte_Array;
      Status        : out Status_Code)
   is
      Read_Status  : Status_Code := Ok;
      Write_Status : Status_Code := Ok;
      type Payload_Vector_Array is array (Positive range <>) of Byte_Vectors.Vector;
      type Boolean_Array is array (Positive range <>) of Boolean;
      type Metadata_Array is array (Positive range <>) of Seven_Zip_Entry_Metadata;
   begin
      Status := Unsupported_Method;

      if Output_Dir'Length = 0 or else Entry_Names'Length = 0 then
         return;
      end if;

      for Offset in 0 .. Entry_Names'Length - 1 loop
         declare
            Entry_Name : constant String :=
              US.To_String (Entry_Names (Entry_Names'First + Offset));
         begin
            if not Zlib.Seven_Zip_Paths.Safe_Output_Name (Entry_Name) then
               return;
            end if;

            if Offset > 0 then
               for Previous_Offset in 0 .. Offset - 1 loop
                  if Entry_Name =
                    US.To_String
                      (Entry_Names (Entry_Names'First + Previous_Offset))
                  then
                     return;
                  end if;
               end loop;
            end if;
         end;
      end loop;

      if not Zlib.Seven_Zip_Paths.Output_Directory_Writable (Output_Dir) then
         Status := Output_File_Error;
         return;
      end if;

      declare
         Archive : constant Byte_Array := Read_File (Input_Path, Read_Status);
      begin
         if Read_Status /= Ok then
            Status := Read_Status;
            return;
         end if;

         declare
            Payloads : Payload_Vector_Array (1 .. Entry_Names'Length);
            Is_Directory : Boolean_Array (1 .. Entry_Names'Length) :=
              [others => False];
            Entry_Metadata : Metadata_Array (1 .. Entry_Names'Length) :=
              [others => No_Seven_Zip_Entry_Metadata];
         begin
            for Offset in 0 .. Entry_Names'Length - 1 loop
               declare
                  Entry_Name : constant String :=
                    US.To_String (Entry_Names (Entry_Names'First + Offset));
                  Directory_Entry : Boolean := False;
                  Metadata : Seven_Zip_Entry_Metadata;
                  Payload : constant Byte_Array :=
                    Extract_Entry
                      (Archive, Entry_Name, Status, Directory_Entry, Metadata);
               begin
                  if Status /= Ok then
                     return;
                  end if;

                  Is_Directory (Offset + 1) := Directory_Entry;
                  Entry_Metadata (Offset + 1) := Metadata;
                  for B of Payload loop
                     Payloads (Offset + 1).Append (B);
                  end loop;
               end;
            end loop;

            begin
               Ada.Directories.Create_Path (Output_Dir);
            exception
               when others =>
                  Status := Output_File_Error;
                  return;
            end;

            for Offset in 0 .. Entry_Names'Length - 1 loop
               declare
                  Entry_Name : constant String :=
                    US.To_String (Entry_Names (Entry_Names'First + Offset));
                  Output_Path : constant String :=
                    Zlib.Seven_Zip_Paths.Output_Path (Output_Dir, Entry_Name);
                  Parent_Path : constant String :=
                    Ada.Directories.Containing_Directory (Output_Path);
               begin
                  begin
                     if Ada.Directories.Exists (Output_Path)
                       and then
                        Ada.Directories.Kind (Output_Path) =
                           Ada.Directories.Directory
                       and then not Is_Directory (Offset + 1)
                     then
                        Status := Output_File_Error;
                        return;
                     end if;

                     if Ada.Directories.Exists (Parent_Path)
                       and then
                         Ada.Directories.Kind (Parent_Path) /=
                           Ada.Directories.Directory
                     then
                        Status := Output_File_Error;
                        return;
                     end if;
                  exception
                     when others =>
                        Status := Output_File_Error;
                        return;
                  end;
               end;
            end loop;

            for Offset in 0 .. Entry_Names'Length - 1 loop
               declare
                  Entry_Name : constant String :=
                    US.To_String (Entry_Names (Entry_Names'First + Offset));
                  Output_Path : constant String :=
                    Zlib.Seven_Zip_Paths.Output_Path (Output_Dir, Entry_Name);
                  Payload : constant Byte_Array :=
                    To_Byte_Array (Payloads (Offset + 1));
               begin
                  if Is_Directory (Offset + 1) then
                     begin
                        Ada.Directories.Create_Path (Output_Path);
                     exception
                        when others =>
                           Status := Output_File_Error;
                           return;
                     end;
                     Zlib.Seven_Zip_Properties.Apply_Metadata
                       (Output_Path, Entry_Metadata (Offset + 1));
                  else
                     begin
                        Ada.Directories.Create_Path
                          (Ada.Directories.Containing_Directory (Output_Path));
                     exception
                        when others =>
                           Status := Output_File_Error;
                           return;
                     end;

                     Write_File (Output_Path, Payload, Write_Status);
                     if Write_Status /= Ok then
                        Status := Write_Status;
                        return;
                     end if;

                     Zlib.Seven_Zip_Properties.Apply_Metadata
                       (Output_Path, Entry_Metadata (Offset + 1));
                  end if;
               end;
            end loop;
         end;

         Status := Ok;
      end;
   exception
      when others =>
         Status := Output_File_Error;
   end Extract_Files;

end Zlib.Seven_Zip_File_Extraction;
