with Ada.Command_Line;
with Ada.Text_IO;
with Example_Raw_Support;
with Zlib;

procedure Raw_Vs_Zlib_Vs_Gzip is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   Input  : constant Zlib.Byte_Array := Example_Raw_Support.Plain;
   Status : Zlib.Status_Code;
   Raw    : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Input, Zlib.Auto, Status);

   function Has_Zlib_Header (Data : Zlib.Byte_Array) return Boolean is
   begin
      return Data'Length >= 2
        and then Data (Data'First) = 16#78#
        and then (Natural (Data (Data'First)) * 256 + Natural (Data (Data'First + 1))) mod 31 = 0;
   end Has_Zlib_Header;

   function Has_Gzip_Header (Data : Zlib.Byte_Array) return Boolean is
   begin
      return Data'Length >= 2
        and then Data (Data'First) = 16#1F#
        and then Data (Data'First + 1) = 16#8B#;
   end Has_Gzip_Header;

   procedure Show (Name : String; Size : Natural; ZH : Boolean; GH : Boolean) is
   begin
      Ada.Text_IO.Put_Line
        (Name & " size=" & Natural'Image (Size)
         & " zlib-header=" & Boolean'Image (ZH)
         & " gzip-header=" & Boolean'Image (GH));
   end Show;
begin
   if Status /= Zlib.Ok then
      Ada.Text_IO.Put_Line ("raw compression failed: " & Zlib.Status_Image (Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Zdata : constant Zlib.Byte_Array := Zlib.Deflate (Input, Zlib.Auto, Status);
   begin
      if Status /= Zlib.Ok then
         Ada.Text_IO.Put_Line ("zlib compression failed: " & Zlib.Status_Image (Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      declare
         Gdata : constant Zlib.Byte_Array := Zlib.GZip (Input, Zlib.Auto, Status);
      begin
         if Status /= Zlib.Ok then
            Ada.Text_IO.Put_Line ("gzip compression failed: " & Zlib.Status_Image (Status));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         Show ("raw ", Raw'Length, Has_Zlib_Header (Raw), Has_Gzip_Header (Raw));
         Show ("zlib", Zdata'Length, Has_Zlib_Header (Zdata), Has_Gzip_Header (Zdata));
         Show ("gzip", Gdata'Length, Has_Zlib_Header (Gdata), Has_Gzip_Header (Gdata));
      end;
   end;
exception
   when Zlib.Zlib_Error | Zlib.Status_Error =>
      Ada.Text_IO.Put_Line ("wrapper comparison example raised Zlib error");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Raw_Vs_Zlib_Vs_Gzip;
