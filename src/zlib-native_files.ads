--  Support level: private internal implementation.
--
--  Every by-path file and directory operation of the crate goes through here:
--  opening and creating Stream_IO files, asking whether a path exists and what
--  it is, its size and times, creating, deleting, renaming and listing.
--
--  GNAT's Windows runtime refuses a path longer than 260 characters in
--  System.File_IO (Stream_IO Open and Create raise Name_Error "file name too
--  long"), Ada.Directories and GNAT.OS_Lib, before Windows is ever asked, so
--  an archive deep in a tree could be neither read nor extracted there. The
--  Windows body therefore talks to the wide Win32 and CRT entry points itself,
--  with the path converted to UTF-16 and, when long, given the \\?\ form of
--  Zlib.Windows_Paths. The POSIX body hands every call to the Ada and GNAT
--  libraries unchanged, which have no such limit there.
--
--  Paths are UTF-8 text, the same as everywhere else in the crate. Failures
--  raise the Ada.IO_Exceptions exceptions the matching Ada.Directories or
--  Stream_IO call raises, so callers handle them as before.
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Calendar;
with Ada.Strings.Unbounded;

package Zlib.Native_Files is

   subtype File_Size is Ada.Directories.File_Size;
   --  A file's length in bytes.

   type File_Kind is (Missing, Directory, Ordinary_File, Special_File);
   --  What a path names; Missing when nothing can be found there.

   function Kind (Path : String) return File_Kind;
   --  What Path names; Missing when nothing can be found there, including
   --  when a parent cannot be read. Like Ada.Directories.Exists, raises
   --  Name_Error when Path is not a valid path name (empty, or holding NUL).

   function Exists (Path : String) return Boolean is (Kind (Path) /= Missing);
   --  Whether anything is found at Path; Name_Error as for Kind.

   function Size (Path : String) return File_Size;
   --  The length of the ordinary file at Path. Raises Name_Error when Path is
   --  not an ordinary file.

   function Modification_Time (Path : String) return Ada.Calendar.Time;
   --  When the file or directory at Path was last modified. Raises Name_Error
   --  when nothing is there, Use_Error when the time cannot be read.

   function Is_Owner_Writable (Path : String) return Boolean;
   --  Whether the file or directory at Path may be written by its owner (on
   --  Windows: whether it lacks the read-only attribute). False when missing.

   procedure Set_Modification_Time (Path : String; Unix_Seconds : Long_Long_Integer);
   --  Give the file or directory at Path the modification (and access) time
   --  Unix_Seconds, whole seconds since 1970-01-01 UTC. Like
   --  GNAT.OS_Lib.Set_File_Last_Modify_Time_Stamp, a failure is silent. Taken
   --  as seconds, not an OS_Time: GNAT.OS_Lib.GM_Time_Of reads local time,
   --  and newer runtimes no longer declare the time_t To_Ada takes.

   procedure Set_Read_Only (Path : String);
   --  Make the file or directory at Path read-only. Like GNAT.OS_Lib's
   --  Set_Read_Only, a failure is silent.

   procedure Open
     (File : in out Ada.Streams.Stream_IO.File_Type;
      Mode : Ada.Streams.Stream_IO.File_Mode;
      Name : String;
      Form : String := "shared=no");
   --  Ada.Streams.Stream_IO.Open for the existing file Name, at any length.
   --  Raises Name_Error when there is no such file, Use_Error when it cannot
   --  be opened.

   procedure Create
     (File : in out Ada.Streams.Stream_IO.File_Type;
      Mode : Ada.Streams.Stream_IO.File_Mode := Ada.Streams.Stream_IO.Out_File;
      Name : String;
      Form : String := "shared=no");
   --  Ada.Streams.Stream_IO.Create for the file Name, at any length: a new
   --  empty file, replacing any that was there. Raises Name_Error or
   --  Use_Error when it cannot be created.

   procedure Create_Directory (Path : String);
   --  Create the directory Path, whose parent must exist. Raises Use_Error
   --  when it cannot be created (including when something is already there).

   procedure Create_Path (Path : String);
   --  Create the directory Path together with every missing ancestor. Nothing
   --  happens when Path already is a directory; Use_Error is raised when it,
   --  or an ancestor, is something else or cannot be created.

   procedure Delete_File (Path : String);
   --  Delete the ordinary file Path. Raises Name_Error when it is not an
   --  ordinary file, Use_Error when it cannot be deleted.

   procedure Delete_Directory (Path : String);
   --  Delete the empty directory Path. Raises Name_Error when it is not a
   --  directory, Use_Error when it cannot be deleted.

   procedure Delete_Tree (Path : String);
   --  Delete the directory Path with everything in it. Raises Name_Error when
   --  it is not a directory, Use_Error when something in it cannot be deleted.

   procedure Rename (Old_Path : String; New_Path : String);
   --  Give the file or directory Old_Path the name New_Path, which must not
   --  exist yet. Raises Name_Error when Old_Path is missing, Use_Error when
   --  the rename fails.

   function Containing_Directory (Path : String) return String;
   --  The directory part of Path, as Ada.Directories.Containing_Directory
   --  computes it. Pure text: the file system is not consulted.

   function Simple_Name (Path : String) return String;
   --  The last component of Path, as Ada.Directories.Simple_Name computes it.
   --  Pure text: the file system is not consulted.

   type Directory_Entry is record
      Name : Ada.Strings.Unbounded.Unbounded_String;
      --  The entry's simple name, UTF-8.
      Kind : File_Kind := Missing;
      --  What the entry is.
   end record;
   --  One entry of a directory listing.

   type Directory_Entries is array (Positive range <>) of Directory_Entry;
   --  A directory listing, in the order the system gives it.

   function List_Directory (Path : String) return Directory_Entries;
   --  The entries of the directory Path, without "." and "..". Raises
   --  Name_Error when Path is not a directory, Use_Error when it cannot be
   --  read.

end Zlib.Native_Files;
