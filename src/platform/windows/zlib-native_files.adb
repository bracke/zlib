with Ada.Calendar.Formatting;
with Ada.Containers.Vectors;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO.C_Streams;
with Ada.Strings.UTF_Encoding.Conversions;
with GNAT.OS_Lib;
with Interfaces.C;
with Interfaces.C_Streams;
with System.Storage_Elements;
with Zlib.Windows_Paths;

--  Windows: GNAT's System.File_IO, Ada.Directories and GNAT.OS_Lib copy every
--  path into a MAX_PATH buffer and refuse a longer one before Windows is asked,
--  so each operation here calls the wide Win32 or CRT entry point itself, with
--  the path as UTF-16 in the \\?\ form Zlib.Windows_Paths gives a long one.
--  Stream_IO files are opened with _wfopen and handed to Stream_IO through
--  Ada.Streams.Stream_IO.C_Streams, so callers read and write them as before.
package body Zlib.Native_Files is

   use type Interfaces.C.int;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type System.Address;
   use type Ada.Calendar.Time;
   use type Ada.Streams.Stream_IO.File_Mode;

   subtype DWord is Interfaces.Unsigned_32;
   subtype Win_Bool is Interfaces.C.int;

   File_Attribute_Read_Only : constant DWord := 16#0000_0001#;
   File_Attribute_Directory : constant DWord := 16#0000_0010#;
   File_Attribute_Device    : constant DWord := 16#0000_0040#;
   Invalid_File_Attributes  : constant DWord := 16#FFFF_FFFF#;

   File_Write_Attributes      : constant DWord := 16#0000_0100#;
   File_Share_All             : constant DWord := 16#0000_0007#;
   Open_Existing              : constant DWord := 3;
   File_Flag_Backup_Semantics : constant DWord := 16#0200_0000#;
   Move_File_Copy_Allowed     : constant DWord := 16#0000_0002#;

   Get_File_Ex_Info_Standard : constant Interfaces.C.int := 0;

   No_Such_File : constant := 2;
   --  ENOENT, as the CRT reports a missing file or directory in errno.

   Invalid_Handle : constant System.Address :=
     System.Storage_Elements.To_Address (System.Storage_Elements.Integer_Address'Last);
   --  INVALID_HANDLE_VALUE, all bits set.

   Ticks_Per_Second : constant := 10_000_000;
   Unix_Epoch_Ticks : constant := 116_444_736_000_000_000;
   --  A FILETIME counts 100 ns ticks from 1601-01-01 UTC; this many of them
   --  lie before 1970-01-01 UTC.

   type File_Time is record
      Low  : DWord;
      High : DWord;
   end record
     with Convention => C;
   --  FILETIME.

   type Attribute_Data is record
      Attributes  : DWord;
      Creation    : File_Time;
      Last_Access : File_Time;
      Last_Write  : File_Time;
      Size_High   : DWord;
      Size_Low    : DWord;
   end record
     with Convention => C;
   --  WIN32_FILE_ATTRIBUTE_DATA.

   type Find_Data is record
      Attributes     : DWord;
      Creation       : File_Time;
      Last_Access    : File_Time;
      Last_Write     : File_Time;
      Size_High      : DWord;
      Size_Low       : DWord;
      Reserved_0     : DWord;
      Reserved_1     : DWord;
      File_Name      : Wide_String (1 .. 260);
      Alternate_Name : Wide_String (1 .. 14);
   end record
     with Convention => C;
   --  WIN32_FIND_DATAW.

   function Get_File_Attributes_Ex
     (Name  : System.Address;
      Level : Interfaces.C.int;
      Data  : access Attribute_Data) return Win_Bool
     with Import, Convention => Stdcall, External_Name => "GetFileAttributesExW";

   function Get_File_Attributes (Name : System.Address) return DWord
     with Import, Convention => Stdcall, External_Name => "GetFileAttributesW";

   function Set_File_Attributes (Name : System.Address; Attributes : DWord) return Win_Bool
     with Import, Convention => Stdcall, External_Name => "SetFileAttributesW";

   function Create_Directory_W (Name : System.Address; Security : System.Address) return Win_Bool
     with Import, Convention => Stdcall, External_Name => "CreateDirectoryW";

   function Remove_Directory_W (Name : System.Address) return Win_Bool
     with Import, Convention => Stdcall, External_Name => "RemoveDirectoryW";

   function Delete_File_W (Name : System.Address) return Win_Bool
     with Import, Convention => Stdcall, External_Name => "DeleteFileW";

   function Move_File_Ex
     (Existing : System.Address;
      New_Name : System.Address;
      Flags    : DWord) return Win_Bool
     with Import, Convention => Stdcall, External_Name => "MoveFileExW";

   function Find_First_File (Name : System.Address; Data : access Find_Data) return System.Address
     with Import, Convention => Stdcall, External_Name => "FindFirstFileW";

   function Find_Next_File (Handle : System.Address; Data : access Find_Data) return Win_Bool
     with Import, Convention => Stdcall, External_Name => "FindNextFileW";

   function Find_Close (Handle : System.Address) return Win_Bool
     with Import, Convention => Stdcall, External_Name => "FindClose";

   function Create_File
     (Name        : System.Address;
      Access_Mask : DWord;
      Share_Mode  : DWord;
      Security    : System.Address;
      Disposition : DWord;
      Flags       : DWord;
      Template    : System.Address) return System.Address
     with Import, Convention => Stdcall, External_Name => "CreateFileW";

   function Set_File_Time
     (Handle      : System.Address;
      Creation    : System.Address;
      Last_Access : System.Address;
      Last_Write  : access constant File_Time) return Win_Bool
     with Import, Convention => Stdcall, External_Name => "SetFileTime";

   function Close_Handle (Handle : System.Address) return Win_Bool
     with Import, Convention => Stdcall, External_Name => "CloseHandle";

   function W_Fopen (Name : System.Address; Mode : System.Address) return Interfaces.C_Streams.FILEs
     with Import, Convention => C, External_Name => "_wfopen";

   procedure Ignore (Result : Win_Bool) is
      pragma Unreferenced (Result);
   begin
      null;
   end Ignore;
   --  For the calls whose failure the operation deliberately does not report.

   --  Path as the wide API takes it; Name_Error when Path is not UTF-8.
   function Wide (Path : String) return Wide_String is
   begin
      return Zlib.Windows_Paths.Native (Path);
   exception
      when Ada.Strings.UTF_Encoding.Encoding_Error =>
         raise Ada.IO_Exceptions.Name_Error with "file name is not UTF-8: " & Path;
   end Wide;

   function Is_Separator (Item : Character) return Boolean is (Item in '\' | '/');

   function Join (Directory_Path : String; Name : String) return String is
     (if Directory_Path'Length > 0 and then Is_Separator (Directory_Path (Directory_Path'Last))
      then Directory_Path & Name
      else Directory_Path & "\" & Name);

   function To_Ticks (Time : File_Time) return Interfaces.Unsigned_64 is
     (Interfaces.Shift_Left (Interfaces.Unsigned_64 (Time.High), 32) or Interfaces.Unsigned_64 (Time.Low));

   function Kind_Of (Attributes : DWord) return File_Kind is
     (if (Attributes and File_Attribute_Directory) /= 0 then Directory
      elsif (Attributes and File_Attribute_Device) /= 0 then Special_File
      else Ordinary_File);

   --  The attribute data of Path, or False when Windows finds nothing there
   --  (or the path is not valid UTF-8).
   function Attributes_Of (Path : String; Data : out Attribute_Data) return Boolean is
      Found : aliased Attribute_Data :=
        (Attributes => 0, Creation | Last_Access | Last_Write => (Low => 0, High => 0), Size_High | Size_Low => 0);
   begin
      Data := Found;
      if Path'Length = 0 then
         return False;
      end if;
      declare
         Name : aliased constant Wide_String := Wide (Path);
      begin
         if Get_File_Attributes_Ex (Name'Address, Get_File_Ex_Info_Standard, Found'Access) = 0 then
            return False;
         end if;
      end;
      Data := Found;
      return True;
   exception
      when Ada.IO_Exceptions.Name_Error =>
         return False;
   end Attributes_Of;

   function Kind (Path : String) return File_Kind is
      Data : Attribute_Data;
   begin
      if Path'Length = 0 or else (for some Item of Path => Item = ASCII.NUL) then
         raise Ada.IO_Exceptions.Name_Error with "invalid path name """ & Path & '"';
      end if;
      if not Attributes_Of (Path, Data) then
         return Missing;
      end if;
      return Kind_Of (Data.Attributes);
   end Kind;

   function Size (Path : String) return File_Size is
      Data : Attribute_Data;
   begin
      if not Attributes_Of (Path, Data) or else Kind_Of (Data.Attributes) /= Ordinary_File then
         raise Ada.IO_Exceptions.Name_Error with "not an ordinary file: " & Path;
      end if;
      return File_Size (Interfaces.Shift_Left (Interfaces.Unsigned_64 (Data.Size_High), 32)
                        or Interfaces.Unsigned_64 (Data.Size_Low));
   end Size;

   function Modification_Time (Path : String) return Ada.Calendar.Time is
      Data : Attribute_Data;
   begin
      if not Attributes_Of (Path, Data) then
         raise Ada.IO_Exceptions.Name_Error with "not a file or directory: " & Path;
      end if;
      declare
         Unix_Epoch : constant Ada.Calendar.Time := Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0, 0, 0);
         Ticks      : constant Interfaces.Unsigned_64 := To_Ticks (Data.Last_Write);
      begin
         if Ticks >= Unix_Epoch_Ticks then
            declare
               Since : constant Interfaces.Unsigned_64 := Ticks - Unix_Epoch_Ticks;
            begin
               return Unix_Epoch + Duration (Since / Ticks_Per_Second)
                 + Duration (Since mod Ticks_Per_Second) / Ticks_Per_Second;
            end;
         else
            declare
               Before : constant Interfaces.Unsigned_64 := Unix_Epoch_Ticks - Ticks;
            begin
               return Unix_Epoch - Duration (Before / Ticks_Per_Second)
                 - Duration (Before mod Ticks_Per_Second) / Ticks_Per_Second;
            end;
         end if;
      end;
   exception
      when Constraint_Error | Ada.Calendar.Time_Error =>
         raise Ada.IO_Exceptions.Use_Error with "modification time out of range: " & Path;
   end Modification_Time;

   function Is_Owner_Writable (Path : String) return Boolean is
      Data : Attribute_Data;
   begin
      return Attributes_Of (Path, Data) and then (Data.Attributes and File_Attribute_Read_Only) = 0;
   end Is_Owner_Writable;

   procedure Set_Modification_Time (Path : String; Unix_Seconds : Long_Long_Integer) is
      Seconds : constant Long_Long_Integer := Unix_Seconds;
   begin
      if Seconds < -11_644_473_600 then
         return;
      end if;
      declare
         Ticks : constant Interfaces.Unsigned_64 :=
           Interfaces.Unsigned_64 (Seconds + 11_644_473_600) * Ticks_Per_Second;
         Stamp : aliased constant File_Time :=
           (Low  => DWord (Ticks and 16#FFFF_FFFF#),
            High => DWord (Interfaces.Shift_Right (Ticks, 32)));
         Name   : aliased constant Wide_String := Wide (Path);
         Handle : constant System.Address :=
           Create_File
             (Name'Address, File_Write_Attributes, File_Share_All, System.Null_Address, Open_Existing,
              File_Flag_Backup_Semantics, System.Null_Address);
      begin
         if Handle = Invalid_Handle then
            return;
         end if;
         Ignore (Set_File_Time (Handle, System.Null_Address, System.Null_Address, Stamp'Access));
         Ignore (Close_Handle (Handle));
      end;
   exception
      when Constraint_Error | Ada.IO_Exceptions.Name_Error =>
         return;
   end Set_Modification_Time;

   procedure Set_Read_Only (Path : String) is
   begin
      declare
         Name       : aliased constant Wide_String := Wide (Path);
         Attributes : constant DWord := Get_File_Attributes (Name'Address);
      begin
         if Attributes /= Invalid_File_Attributes then
            Ignore (Set_File_Attributes (Name'Address, Attributes or File_Attribute_Read_Only));
         end if;
      end;
   exception
      when Ada.IO_Exceptions.Name_Error =>
         return;
   end Set_Read_Only;

   --  Open Name with the _wfopen mode Wide_Mode and hand the stream to File.
   procedure Open_Stream
     (File      : in out Ada.Streams.Stream_IO.File_Type;
      Mode      : Ada.Streams.Stream_IO.File_Mode;
      Name      : String;
      Form      : String;
      Wide_Mode : Wide_String)
   is
      Native : aliased constant Wide_String := Wide (Name);
      C_Mode : aliased constant Wide_String := Wide_Mode & Wide_Character'Val (0);
      Stream : Interfaces.C_Streams.FILEs;
   begin
      if Ada.Streams.Stream_IO.Is_Open (File) then
         raise Ada.IO_Exceptions.Status_Error with "file already open";
      end if;

      Stream := W_Fopen (Native'Address, C_Mode'Address);
      if Stream = Interfaces.C_Streams.NULL_Stream then
         if GNAT.OS_Lib.Errno = No_Such_File then
            raise Ada.IO_Exceptions.Name_Error with "cannot open " & Name;
         end if;
         raise Ada.IO_Exceptions.Use_Error with "cannot open " & Name;
      end if;

      --  The runtime copies the name it is given into a MAX_PATH buffer of its
      --  own, so a long one is not recorded; Stream_IO.Name then answers "".
      begin
         Ada.Streams.Stream_IO.C_Streams.Open
           (File     => File,
            Mode     => Mode,
            C_Stream => Stream,
            Form     => Form,
            Name     => (if Name'Length < 256 then Name else ""));
      exception
         when others =>
            Ignore (Win_Bool (Interfaces.C_Streams.fclose (Stream)));
            raise;
      end;
   end Open_Stream;

   procedure Open
     (File : in out Ada.Streams.Stream_IO.File_Type;
      Mode : Ada.Streams.Stream_IO.File_Mode;
      Name : String;
      Form : String := "shared=no") is
   begin
      Open_Stream
        (File, Mode, Name, Form,
         (case Mode is
            when Ada.Streams.Stream_IO.In_File     => "rb",
            when Ada.Streams.Stream_IO.Out_File    => "r+b",
            when Ada.Streams.Stream_IO.Append_File => "ab"));
   end Open;

   procedure Create
     (File : in out Ada.Streams.Stream_IO.File_Type;
      Mode : Ada.Streams.Stream_IO.File_Mode := Ada.Streams.Stream_IO.Out_File;
      Name : String;
      Form : String := "shared=no") is
   begin
      if Kind (Name) = Directory then
         raise Ada.IO_Exceptions.Use_Error with "is a directory: " & Name;
      end if;
      Open_Stream (File, Mode, Name, Form, (if Mode = Ada.Streams.Stream_IO.In_File then "w+b" else "wb"));
   end Create;

   procedure Create_Directory (Path : String) is
   begin
      if Path'Length = 0 then
         raise Ada.IO_Exceptions.Name_Error with "empty directory name";
      end if;
      declare
         Name : aliased constant Wide_String := Wide (Path);
      begin
         if Create_Directory_W (Name'Address, System.Null_Address) = 0 then
            raise Ada.IO_Exceptions.Use_Error with "cannot create directory " & Path;
         end if;
      end;
   end Create_Directory;

   --  Path without its last component, keeping the separator before it; ""
   --  when Path has a single component.
   function Parent_Of (Path : String) return String is
      Last : Natural := Path'Last;
   begin
      while Last >= Path'First and then Is_Separator (Path (Last)) loop
         Last := Last - 1;
      end loop;
      while Last >= Path'First and then not Is_Separator (Path (Last)) loop
         Last := Last - 1;
      end loop;
      return Path (Path'First .. Last);
   end Parent_Of;

   procedure Create_Path (Path : String) is
      Current : constant File_Kind := Kind (Path);
   begin
      if Current = Directory then
         return;
      elsif Current /= Missing then
         raise Ada.IO_Exceptions.Use_Error with "not a directory: " & Path;
      end if;

      declare
         Parent : constant String := Parent_Of (Path);
      begin
         --  Each step is strictly shorter, so the walk up ends at the root,
         --  which exists, or at a first component nothing can create.
         if Parent'Length > 0 and then Parent'Length < Path'Length then
            Create_Path (Parent);
         end if;
      end;

      declare
         Name : aliased constant Wide_String := Wide (Path);
      begin
         --  Another process may have made it in the meantime; that is fine.
         if Create_Directory_W (Name'Address, System.Null_Address) = 0 and then Kind (Path) /= Directory then
            raise Ada.IO_Exceptions.Use_Error with "cannot create directory " & Path;
         end if;
      end;
   end Create_Path;

   procedure Delete_File (Path : String) is
   begin
      if Kind (Path) /= Ordinary_File then
         raise Ada.IO_Exceptions.Name_Error with "not an ordinary file: " & Path;
      end if;
      declare
         Name : aliased constant Wide_String := Wide (Path);
      begin
         if Delete_File_W (Name'Address) = 0 then
            raise Ada.IO_Exceptions.Use_Error with "cannot delete " & Path;
         end if;
      end;
   end Delete_File;

   procedure Delete_Directory (Path : String) is
   begin
      if Kind (Path) /= Directory then
         raise Ada.IO_Exceptions.Name_Error with "not a directory: " & Path;
      end if;
      declare
         Name : aliased constant Wide_String := Wide (Path);
      begin
         if Remove_Directory_W (Name'Address) = 0 then
            raise Ada.IO_Exceptions.Use_Error with "cannot delete directory " & Path;
         end if;
      end;
   end Delete_Directory;

   procedure Delete_Tree (Path : String) is
   begin
      for Item of List_Directory (Path) loop
         declare
            Child : constant String := Join (Path, Ada.Strings.Unbounded.To_String (Item.Name));
         begin
            if Item.Kind = Directory then
               Delete_Tree (Child);
            else
               Delete_File (Child);
            end if;
         end;
      end loop;
      Delete_Directory (Path);
   end Delete_Tree;

   procedure Rename (Old_Path : String; New_Path : String) is
   begin
      if Kind (Old_Path) = Missing then
         raise Ada.IO_Exceptions.Name_Error with "no such file or directory: " & Old_Path;
      elsif Kind (New_Path) /= Missing then
         raise Ada.IO_Exceptions.Use_Error with "already exists: " & New_Path;
      end if;
      declare
         Old_Name : aliased constant Wide_String := Wide (Old_Path);
         New_Name : aliased constant Wide_String := Wide (New_Path);
      begin
         if Move_File_Ex (Old_Name'Address, New_Name'Address, Move_File_Copy_Allowed) = 0 then
            raise Ada.IO_Exceptions.Use_Error with "cannot rename " & Old_Path & " to " & New_Path;
         end if;
      end;
   end Rename;

   function Containing_Directory (Path : String) return String is
     (Ada.Directories.Containing_Directory (Path));

   function Simple_Name (Path : String) return String is
     (Ada.Directories.Simple_Name (Path));

   package Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Directory_Entry);

   function List_Directory (Path : String) return Directory_Entries is
      Entries : Entry_Vectors.Vector;
   begin
      if Kind (Path) /= Directory then
         raise Ada.IO_Exceptions.Name_Error with "not a directory: " & Path;
      end if;

      declare
         Pattern : aliased constant Wide_String := Wide (Join (Path, "*"));
         Data    : aliased Find_Data;
         Handle  : constant System.Address := Find_First_File (Pattern'Address, Data'Access);
      begin
         if Handle = Invalid_Handle then
            raise Ada.IO_Exceptions.Use_Error with "cannot list " & Path;
         end if;

         loop
            declare
               Last : Natural := 0;
            begin
               while Last < Data.File_Name'Last and then Data.File_Name (Last + 1) /= Wide_Character'Val (0) loop
                  Last := Last + 1;
               end loop;
               declare
                  Name : constant String :=
                    Ada.Strings.UTF_Encoding.Conversions.Convert (Data.File_Name (1 .. Last));
               begin
                  if Name /= "." and then Name /= ".." then
                     Entries.Append
                       (Directory_Entry'(Name => Ada.Strings.Unbounded.To_Unbounded_String (Name),
                         Kind => Kind_Of (Data.Attributes)));
                  end if;
               end;
            end;
            exit when Find_Next_File (Handle, Data'Access) = 0;
         end loop;
         Ignore (Find_Close (Handle));
      exception
         --  A name Windows holds that is not valid UTF-16 cannot be told.
         when Ada.Strings.UTF_Encoding.Encoding_Error =>
            Ignore (Find_Close (Handle));
            raise Ada.IO_Exceptions.Use_Error with "cannot list " & Path;
      end;

      return Result : Directory_Entries (1 .. Natural (Entries.Length)) do
         for Index in Result'Range loop
            Result (Index) := Entries (Index);
         end loop;
      end return;
   end List_Directory;

end Zlib.Native_Files;
