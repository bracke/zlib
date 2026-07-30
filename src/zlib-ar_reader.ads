--  Support level: private internal implementation.
--
--  Unix "ar" archive reader (the "!<arch>" common variant produced by GNU ar,
--  BSD ar, and the .deb/.a toolchains). Members are stored uncompressed one
--  after another behind 60-byte headers, so the reader indexes the headers of
--  a file on disk and streams a named member's bytes straight from it without
--  holding the archive in memory. The GNU "//" long-name table, the BSD "#1/"
--  in-band long names, and the "/" symbol table are all understood. The root
--  Zlib package is the sole public entry point.
package Zlib.Ar_Reader is

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

end Zlib.Ar_Reader;
