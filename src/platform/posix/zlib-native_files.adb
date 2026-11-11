with Ada.Containers.Vectors;
with Ada.IO_Exceptions;

--  POSIX hosts (Linux, macOS, the BSDs): the Ada and GNAT libraries reach the
--  system with the path as given and no length limit of their own, so every
--  operation is theirs, unchanged.
package body Zlib.Native_Files is

   function Kind (Path : String) return File_Kind is
   begin
      if not Ada.Directories.Exists (Path) then
         return Missing;
      end if;
      case Ada.Directories.Kind (Path) is
         when Ada.Directories.Directory =>
            return Directory;
         when Ada.Directories.Ordinary_File =>
            return Ordinary_File;
         when Ada.Directories.Special_File =>
            return Special_File;
      end case;
   end Kind;

   function Size (Path : String) return File_Size is (Ada.Directories.Size (Path));

   function Modification_Time (Path : String) return Ada.Calendar.Time is
     (Ada.Directories.Modification_Time (Path));

   function Is_Owner_Writable (Path : String) return Boolean is
     (GNAT.OS_Lib.Is_Owner_Writable_File (Path));

   procedure Set_Modification_Time (Path : String; Time : GNAT.OS_Lib.OS_Time) is
   begin
      GNAT.OS_Lib.Set_File_Last_Modify_Time_Stamp (Path, Time);
   end Set_Modification_Time;

   procedure Set_Read_Only (Path : String) is
   begin
      GNAT.OS_Lib.Set_Read_Only (Path);
   end Set_Read_Only;

   procedure Open
     (File : in out Ada.Streams.Stream_IO.File_Type;
      Mode : Ada.Streams.Stream_IO.File_Mode;
      Name : String;
      Form : String := "shared=no") is
   begin
      Ada.Streams.Stream_IO.Open (File, Mode, Name, Form);
   end Open;

   procedure Create
     (File : in out Ada.Streams.Stream_IO.File_Type;
      Mode : Ada.Streams.Stream_IO.File_Mode := Ada.Streams.Stream_IO.Out_File;
      Name : String;
      Form : String := "shared=no") is
   begin
      Ada.Streams.Stream_IO.Create (File, Mode, Name, Form);
   end Create;

   procedure Create_Directory (Path : String) is
   begin
      Ada.Directories.Create_Directory (Path);
   end Create_Directory;

   procedure Create_Path (Path : String) is
   begin
      Ada.Directories.Create_Path (Path);
   end Create_Path;

   procedure Delete_File (Path : String) is
   begin
      Ada.Directories.Delete_File (Path);
   end Delete_File;

   procedure Delete_Directory (Path : String) is
   begin
      Ada.Directories.Delete_Directory (Path);
   end Delete_Directory;

   procedure Delete_Tree (Path : String) is
   begin
      Ada.Directories.Delete_Tree (Path);
   end Delete_Tree;

   procedure Rename (Old_Path : String; New_Path : String) is
   begin
      Ada.Directories.Rename (Old_Path, New_Path);
   end Rename;

   function Containing_Directory (Path : String) return String is
     (Ada.Directories.Containing_Directory (Path));

   function Simple_Name (Path : String) return String is
     (Ada.Directories.Simple_Name (Path));

   package Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Directory_Entry);

   function List_Directory (Path : String) return Directory_Entries is
      Search  : Ada.Directories.Search_Type;
      Item    : Ada.Directories.Directory_Entry_Type;
      Entries : Entry_Vectors.Vector;
   begin
      if Kind (Path) /= Directory then
         raise Ada.IO_Exceptions.Name_Error with "not a directory: " & Path;
      end if;
      Ada.Directories.Start_Search (Search, Path, "");
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Item);
         begin
            if Name /= "." and then Name /= ".." then
               Entries.Append
                 (Directory_Entry'(Name => Ada.Strings.Unbounded.To_Unbounded_String (Name),
                   Kind =>
                     (case Ada.Directories.Kind (Item) is
                        when Ada.Directories.Directory     => Directory,
                        when Ada.Directories.Ordinary_File => Ordinary_File,
                        when Ada.Directories.Special_File  => Special_File)));
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);

      return Result : Directory_Entries (1 .. Natural (Entries.Length)) do
         for Index in Result'Range loop
            Result (Index) := Entries (Index);
         end loop;
      end return;
   exception
      when others =>
         Ada.Directories.End_Search (Search);
         raise;
   end List_Directory;

end Zlib.Native_Files;
