--  Support level: private internal implementation.
--
--  Seek-based ZIP extraction. The central directory is read from the archive
--  file and each member is then streamed from that file straight to its output
--  file, so working memory is bounded by the fixed chunk buffers rather than by
--  the archive size or by the size of any one member.
--
--  A ZIP cannot be decoded front to back: the central directory lives at the
--  end of the file. This package therefore seeks rather than streaming
--  sequentially, which is why it takes a path instead of an input stream.

package Zlib.ZIP_Streaming_Extraction is
   pragma Elaborate_Body;

   procedure Extract_To_Directory
     (Archive_Path    : String;
      Destination_Dir : String;
      Safe_Entry_Name : not null access function
        (Entry_Name : String) return Boolean;
      Extract_Image   : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Status        : out Status_Code) return Byte_Array;
      Handled         : out Boolean;
      Status          : out Status_Code);
   --  Extract every member of the ZIP at Archive_Path below Destination_Dir,
   --  creating subdirectories and recreating directory entries.
   --
   --  Members whose method is neither Stored nor Deflate are not streamed.
   --  Rather than giving up on the whole archive, such a member is rebuilt as a
   --  single-entry image holding only its own compressed bytes and handed to
   --  Extract_Image, so the cost is that one member rather than the archive.
   --
   --  Handled is False only when the archive as a whole is out of scope: an
   --  encrypted member, or a container this reader does not recognize. The
   --  caller must then fall back to whole-image extraction, and Status carries
   --  no meaning. When Handled is True, Status is the deterministic result.
   --  @param Archive_Path path to the .zip file
   --  @param Destination_Dir directory to extract into
   --  @param Safe_Entry_Name predicate rejecting unsafe relative entry paths
   --  @param Extract_Image decodes one entry of a supplied archive image, used
   --  for members this package does not stream
   --  @param Handled False when the caller must fall back to whole-image
   --  extraction
   --  @param Status Ok on success, otherwise a deterministic failure code

   function List_Entries
     (Archive_Path : String;
      Handled      : out Boolean;
      Status       : out Status_Code) return Archive_Entry_Array;
   --  Catalogue every member of the ZIP at Archive_Path by reading only its
   --  central directory, so the cost is proportional to the number of members
   --  rather than to the archive size. Payloads are never touched.
   --
   --  Handled is False when the file is not a ZIP this reader recognizes; the
   --  caller must then fall back to whole-image listing and Status carries no
   --  meaning.
   --  @param Archive_Path path to the .zip file
   --  @param Handled False when the caller must fall back to whole-image
   --  listing
   --  @param Status Ok on success, otherwise a deterministic failure code
   --  @return one Archive_Entry per member when Handled and Status are set

end Zlib.ZIP_Streaming_Extraction;
