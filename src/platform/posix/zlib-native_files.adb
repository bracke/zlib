with Ada.Containers.Vectors;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO.C_Streams;
with GNAT.OS_Lib;
with Interfaces.C;
with Interfaces.C_Streams;
with System;

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

   procedure Set_Modification_Time (Path : String; Unix_Seconds : Long_Long_Integer) is
      --  struct timeval: 64-bit seconds, then microseconds (64-bit on Linux;
      --  32-bit plus padding on 64-bit macOS -- zero either way).
      type Time_Value is record
         Seconds      : Long_Long_Integer;
         Microseconds : Long_Long_Integer;
      end record with Convention => C;
      type Time_Pair is array (1 .. 2) of Time_Value with Convention => C;
      function C_Utimes (Name : System.Address; Times : System.Address) return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "utimes";
      C_Name : aliased constant String := Path & ASCII.NUL;
      Times  : aliased constant Time_Pair := [others => (Seconds => Unix_Seconds, Microseconds => 0)];
      Status : constant Interfaces.C.int := C_Utimes (C_Name'Address, Times'Address);
      pragma Unreferenced (Status);
   begin
      null;
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

   procedure Create_New
     (File : in out Ada.Streams.Stream_IO.File_Type;
      Name : String;
      Form : String := "shared=no")
   is
      use type GNAT.OS_Lib.File_Descriptor;
      use type Interfaces.C_Streams.FILEs;
      C_Mode : aliased constant String := "wb" & ASCII.NUL;
      FD     : GNAT.OS_Lib.File_Descriptor;
      Stream : Interfaces.C_Streams.FILEs;
   begin
      if Ada.Streams.Stream_IO.Is_Open (File) then
         raise Ada.IO_Exceptions.Status_Error with "file already open";
      end if;

      --  GNAT's open_new is open(2) with O_WRONLY | O_CREAT | O_EXCL.
      FD := GNAT.OS_Lib.Create_New_File (Name, GNAT.OS_Lib.Binary);
      if FD = GNAT.OS_Lib.Invalid_FD then
         raise Ada.IO_Exceptions.Use_Error with "cannot create " & Name;
      end if;

      Stream := Interfaces.C_Streams.fdopen (Interfaces.C_Streams.int (FD), C_Mode'Address);
      if Stream = Interfaces.C_Streams.NULL_Stream then
         GNAT.OS_Lib.Close (FD);
         raise Ada.IO_Exceptions.Use_Error with "cannot open " & Name;
      end if;

      begin
         Ada.Streams.Stream_IO.C_Streams.Open
           (File     => File,
            Mode     => Ada.Streams.Stream_IO.Out_File,
            C_Stream => Stream,
            Form     => Form,
            Name     => Name);
      exception
         when others =>
            if Interfaces.C_Streams.fclose (Stream) /= 0 then
               null;
            end if;
            raise;
      end;
   end Create_New;

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

   procedure Replace (Old_Path : String; New_Path : String) is
      use type Interfaces.C.int;
      function C_Rename (Old_Name : System.Address; New_Name : System.Address) return Interfaces.C.int
        with Import => True, Convention => C, External_Name => "rename";
      Old_Name : aliased constant String := Old_Path & ASCII.NUL;
      New_Name : aliased constant String := New_Path & ASCII.NUL;
   begin
      if Kind (Old_Path) = Missing then
         raise Ada.IO_Exceptions.Name_Error with "no such file or directory: " & Old_Path;
      end if;
      if C_Rename (Old_Name'Address, New_Name'Address) /= 0 then
         raise Ada.IO_Exceptions.Use_Error with "cannot rename " & Old_Path & " to " & New_Path;
      end if;
   end Replace;

   function Containing_Directory (Path : String) return String is
     (Ada.Directories.Containing_Directory (Path));

   function Simple_Name (Path : String) return String is
     (Ada.Directories.Simple_Name (Path));

   function Colon_Is_Path_Syntax return Boolean is (False);

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
