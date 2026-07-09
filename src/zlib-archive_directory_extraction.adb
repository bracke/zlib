with Ada.Directories;
with Ada.Strings.Unbounded;

package body Zlib.Archive_Directory_Extraction is

   package US renames Ada.Strings.Unbounded;

   procedure Extract_File_To_Directory
     (Archive_Path    : String;
      Destination_Dir : String;
      Password        : String;
      Read_File       : not null access function
        (Path : String; Status : out Status_Code) return Byte_Array;
      Extract_Image   : not null access procedure
        (Archive_Image   : Byte_Array;
         Destination_Dir : String;
         Password        : String;
         Status          : out Status_Code);
      Status          : out Status_Code)
   is
      Read_Status : Status_Code := Ok;
      Image       : constant Byte_Array := Read_File (Archive_Path, Read_Status);
   begin
      if Read_Status /= Ok then
         Status := Read_Status;
         return;
      end if;

      Extract_Image (Image, Destination_Dir, Password, Status);
   exception
      when others =>
         Status := Unsupported_Method;
   end Extract_File_To_Directory;

   procedure Extract_To_Directory
     (Archive_Image     : Byte_Array;
      Destination_Dir   : String;
      Password          : String;
      Is_Seven_Zip      : Boolean;
      List_Seven_Zip    : not null access function
        (Archive_Image : Byte_Array;
         Password      : String;
         Status        : out Status_Code) return Archive_Entry_Array;
      List_ZIP          : not null access function
        (Archive_Image : Byte_Array;
         Status        : out Status_Code) return Archive_Entry_Array;
      Extract_Seven_Zip : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Password      : String;
         Status        : out Status_Code) return Byte_Array;
      Extract_ZIP       : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Status        : out Status_Code) return Byte_Array;
      Safe_Entry_Name   : not null access function
        (Entry_Name : String) return Boolean;
      Write_File        : not null access procedure
        (Path : String; Data : Byte_Array; Status : out Status_Code);
      Status            : out Status_Code)
   is
      List_Status : Status_Code := Ok;
      Entries     : constant Archive_Entry_Array :=
        (if Is_Seven_Zip
         then List_Seven_Zip (Archive_Image, Password, List_Status)
         else List_ZIP (Archive_Image, List_Status));
   begin
      Status := Unsupported_Method;

      if List_Status /= Ok then
         Status := List_Status;
         return;
      end if;

      for E of Entries loop
         declare
            Name : constant String := US.To_String (E.Name);
            Rel  : constant String :=
              (if Name'Length > 0 and then Name (Name'Last) = '/'
               then Name (Name'First .. Name'Last - 1) else Name);
         begin
            if Rel'Length = 0 or else not Safe_Entry_Name (Rel) then
               Status := Unsupported_Method;
               return;
            end if;

            declare
               Target : constant String := Destination_Dir & "/" & Rel;
            begin
               if E.Is_Directory then
                  Ada.Directories.Create_Path (Target);
               else
                  Ada.Directories.Create_Path
                    (Ada.Directories.Containing_Directory (Target));
                  declare
                     Extract_Status : Status_Code := Ok;
                     Data           : constant Byte_Array :=
                       (if Is_Seven_Zip
                        then Extract_Seven_Zip
                          (Archive_Image, Name, Password, Extract_Status)
                        else Extract_ZIP (Archive_Image, Name, Extract_Status));
                     Write_Status   : Status_Code := Ok;
                  begin
                     if Extract_Status /= Ok then
                        Status := Extract_Status;
                        return;
                     end if;

                     Write_File (Target, Data, Write_Status);
                     if Write_Status /= Ok then
                        Status := Write_Status;
                        return;
                     end if;
                  end;
               end if;
            end;
         end;
      end loop;

      Status := Ok;
   exception
      when others =>
         Status := Unsupported_Method;
   end Extract_To_Directory;

end Zlib.Archive_Directory_Extraction;
