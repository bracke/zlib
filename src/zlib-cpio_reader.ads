--  Support level: private internal implementation.
--
--  cpio "new ASCII" reader (the "070701" newc and "070702" CRC formats GNU
--  cpio and the Linux initramfs toolchain produce). Members are stored
--  uncompressed behind a fixed 110-byte ASCII-hex header followed by a
--  NUL-terminated name, both padded to a 4-byte boundary, so the reader
--  indexes the headers of a file on disk and streams a named regular file's
--  bytes straight from it without holding the archive in memory. The file
--  type (directory, symlink, device, FIFO, socket, regular) is carried in the
--  member's mode, preserved in the entry Metadata. The root Zlib package is
--  the sole public entry point.
package Zlib.Cpio_Reader is

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

end Zlib.Cpio_Reader;
