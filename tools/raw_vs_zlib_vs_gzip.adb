with Ada.Command_Line;
with Ada.Text_IO;
with Zlib;
with Zlib_Tool_Support;

procedure Raw_Vs_Zlib_Vs_Gzip is
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   Status : Zlib.Status_Code;

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

   procedure Show
     (Name : String;
      Data : Zlib.Byte_Array)
   is
   begin
      Ada.Text_IO.Put_Line
        (Name
         & " size=" & Natural'Image (Data'Length)
         & " zlib-header=" & Boolean'Image (Has_Zlib_Header (Data))
         & " gzip-header=" & Boolean'Image (Has_Gzip_Header (Data)));
   end Show;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line ("usage: raw_vs_zlib_vs_gzip INPUT");
   end Usage;
begin
   if Ada.Command_Line.Argument_Count /= 1 then
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Input : constant Zlib.Byte_Array :=
        Zlib_Tool_Support.Read_File (Ada.Command_Line.Argument (1), Status);
   begin
      if Status /= Zlib.Ok then
         Ada.Text_IO.Put_Line (Zlib.Status_Image (Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      declare
         Raw : constant Zlib.Byte_Array := Zlib.Deflate_Raw (Input, Zlib.Auto, Status);
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

               Show ("raw ", Raw);
               Show ("zlib", Zdata);
               Show ("gzip", Gdata);
            end;
         end;
      end;
   end;
exception
   when Zlib.Zlib_Error =>
      Ada.Text_IO.Put_Line ("wrapper comparison zlib error");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when Zlib.Status_Error =>
      Ada.Text_IO.Put_Line ("wrapper comparison lifecycle error");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when others =>
      Ada.Text_IO.Put_Line ("raw_vs_zlib_vs_gzip failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Raw_Vs_Zlib_Vs_Gzip;
