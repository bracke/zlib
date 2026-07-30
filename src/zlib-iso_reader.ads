--  Support level: private internal implementation.
--
--  ISO 9660 ("CD001") reader for the base primary volume descriptor: it walks
--  the directory tree from the root record recorded in the PVD at sector 16,
--  reading only the directory extents (2 KiB metadata sectors) from the file on
--  disk, and streams a named regular file's bytes straight from its data extent
--  without holding the image in memory. Only the plain ISO 9660 name is read;
--  Rock Ridge and Joliet extensions are ignored. Directory recursion is depth-
--  bounded so a cyclic or malformed tree fails closed rather than exhausting
--  the stack. The root Zlib package is the sole public entry point.
package Zlib.Iso_Reader is

   function List_Entries
     (Archive_Path : String;
      Status       : out Status_Code) return Archive_Entry_Array;

   procedure Extract_Entry
     (Archive_Path : String;
      Entry_Name   : String;
      Consumer     : not null access procedure
        (Bytes    : Byte_Array;
         Continue : in out Boolean);
      Status       : out Status_Code);

end Zlib.Iso_Reader;
