with Zlib.Seven_Zip_Container;
with Zlib.Seven_Zip_Filters;
with Zlib.Seven_Zip_Methods; use Zlib.Seven_Zip_Methods;
with Zlib.Seven_Zip_Paths;

package body Zlib.Seven_Zip_Filtered_Writing is

   function Build_Filtered
     (Input          : Byte_Array;
      Entry_Name     : String;
      Filter         : Seven_Zip_Filter_Method;
      Codec          : Seven_Zip_Codec_Method;
      Delta_Distance : Positive;
      Metadata       : Seven_Zip_Entry_Metadata;
      Pack_Filtered  : not null access function
        (Input      : Byte_Array;
         Codec      : Seven_Zip_Codec_Method;
         LZMA_Props : out Byte;
         Status     : out Status_Code) return Byte_Array;
      Status         : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;

      if Delta_Distance not in 1 .. 256
        or else not Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name)
      then
         return Empty;
      end if;

      if Metadata.Is_Directory then
         return
           Zlib.Seven_Zip_Container.Header_Only_Entry
             (Entry_Name, Metadata, Status);
      end if;

      declare
         Filter_Method : constant Seven_Zip_Coder_Method :=
           Method_For_Filter (Filter);
         Codec_Method  : constant Seven_Zip_Coder_Method :=
           Method_For_Codec (Codec);
         Filtered_Data : constant Byte_Array :=
           Zlib.Seven_Zip_Filters.Apply_Filter
             (Input, Filter, Delta_Distance);
         Pack_Status   : Status_Code := Ok;
         LZMA_Props    : Byte := 16#5D#;
         Packed_Data   : constant Byte_Array :=
           Pack_Filtered (Filtered_Data, Codec, LZMA_Props, Pack_Status);
      begin
         if Pack_Status /= Ok then
            Status := Pack_Status;
            return Empty;
         end if;

         return
           Zlib.Seven_Zip_Container.Filtered_Archive
             (Packed_Data, Filtered_Data, Input, Entry_Name, Filter_Method,
              Codec_Method, Delta_Distance, Metadata, Status, LZMA_Props);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Build_Filtered;

end Zlib.Seven_Zip_Filtered_Writing;
