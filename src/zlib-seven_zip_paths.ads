--  Support level: private internal implementation.
--
--  7z path validation helpers shared by native extraction paths.

package Zlib.Seven_Zip_Paths
  with SPARK_Mode => On
is

   function Safe_Output_Name (Entry_Name : String) return Boolean
     with SPARK_Mode => On;
   --  Return True when Entry_Name is a relative, non-empty 7z output name
   --  without NUL bytes, absolute paths, drive-style names, backslashes,
   --  empty path segments, "." segments, or ".." segments. A trailing slash
   --  is accepted for directory entries.

   function Entry_Name_Valid (Entry_Name : String) return Boolean
     with SPARK_Mode => On;
   --  Return True when Entry_Name is non-empty and contains no NUL byte.

   function Entry_Names_Valid (Entry_Names : Text_Array) return Boolean
     with SPARK_Mode => Off;
   --  Return True when every entry name is valid and no name is repeated.

   function Output_File_Writable (Output_Path : String) return Boolean
     with SPARK_Mode => Off;
   --  Return True when Output_Path is non-empty and not an existing directory.

   function Input_Path_Readable (Input_Path : String) return Boolean
     with SPARK_Mode => Off;
   --  Return True when Input_Path is an existing ordinary file or directory.

   function Input_Paths_Readable (Input_Paths : Text_Array) return Boolean
     with SPARK_Mode => Off;
   --  Return True when every input path is readable as a file or directory.

   function Output_Directory_Writable (Output_Dir : String) return Boolean
     with SPARK_Mode => Off;
   --  Return True when Output_Dir exists as a directory, or its parent is usable.

   function Output_Path
     (Output_Dir : String;
      Entry_Name : String) return String
     with SPARK_Mode => Off;
   --  Return the filesystem path for Entry_Name under Output_Dir.

end Zlib.Seven_Zip_Paths;
