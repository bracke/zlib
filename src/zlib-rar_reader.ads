--  Support level: private internal implementation.
--
--  RAR 4.x reader, limited to uncompressed ("Store", method 0x30) members --
--  the only members whose bytes can be produced without the proprietary RAR
--  decompressor. It walks the RAR4 block chain of a file on disk (marker,
--  headers, End_Of_Archive) reading only the headers, and streams a stored,
--  unencrypted regular file's bytes straight from its data area, verifying the
--  header CRC-32. A compressed or encrypted member is catalogued but reports
--  Unsupported_Method on extraction. The RAR5 format and RAR compression are
--  out of scope. The root Zlib package is the sole public entry point.
package Zlib.Rar_Reader is

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

end Zlib.Rar_Reader;
