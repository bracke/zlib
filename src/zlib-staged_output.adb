with Ada.IO_Exceptions;
with Zlib.Native_Files;

package body Zlib.Staged_Output is

   package SIO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;
   use type Zlib.Native_Files.File_Kind;

   Chunk_Size : constant := 64 * 1024;

   Max_Name_Length : constant := 200;
   --  A target name longer than this does not take the suffix: names are
   --  limited to 255 bytes (UTF-16 units on Windows) on common file systems.

   Max_Attempts : constant := 1_000;
   --  Names tried before giving up when every one is taken.

   Suffix : constant String := ".zlib-partial-";

   protected Counter is
      procedure Next (Value : out Natural);
   private
      Last : Natural := 0;
   end Counter;

   protected body Counter is
      procedure Next (Value : out Natural) is
      begin
         Last := (if Last = Natural'Last then 1 else Last + 1);
         Value := Last;
      end Next;
   end Counter;

   function Is_Separator (Item : Character) return Boolean is
     (Item = '/' or else (Item = '\' and then Zlib.Native_Files.Colon_Is_Path_Syntax));

   --  The N-th temporary name for Target, in Target's directory.
   function Temp_Name (Target : String; N : Natural) return String is
      Image      : constant String := Natural'Image (N);
      Tail       : constant String := Suffix & Image (Image'First + 1 .. Image'Last);
      Name_First : Natural := Target'First;
   begin
      for I in reverse Target'Range loop
         if Is_Separator (Target (I)) then
            Name_First := I + 1;
            exit;
         end if;
      end loop;

      if Target'Last - Name_First + 1 <= Max_Name_Length then
         return Target & Tail;
      end if;
      return Target (Target'First .. Name_First - 1) & Tail;
   end Temp_Name;

   procedure Create (Output : in out Staged_File; Target : String) is
   begin
      if Output.Active then
         raise Output_Failed with "output already in progress";
      end if;
      Output.Target := US.To_Unbounded_String (Target);

      for Attempt in 1 .. Max_Attempts loop
         declare
            N    : Natural;
            Temp : US.Unbounded_String;
         begin
            Counter.Next (N);
            Temp := US.To_Unbounded_String (Temp_Name (Target, N));
            begin
               Zlib.Native_Files.Create_New (Output.File, US.To_String (Temp));
               Output.Temp := Temp;
               Output.Active := True;
               return;
            exception
               when Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.Name_Error =>
                  --  Taken: try the next name. Anything else is a refusal no
                  --  other name would get past.
                  if Zlib.Native_Files.Kind (US.To_String (Temp)) = Zlib.Native_Files.Missing then
                     raise Output_Failed with "cannot create a file beside " & Target;
                  end if;
            end;
         end;
      end loop;

      raise Output_Failed with "no free temporary name beside " & Target;
   exception
      when Output_Failed | Storage_Error =>
         raise;
      when others =>
         raise Output_Failed with "cannot create a file beside " & Target;
   end Create;

   procedure Write (Output : in out Staged_File; Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Data'Length > 0 then
         SIO.Write (Output.File, Data);
      end if;
   exception
      when Storage_Error =>
         Discard (Output);
         raise;
      when others =>
         Discard (Output);
         raise Output_Failed with "cannot write " & US.To_String (Output.Target);
   end Write;

   procedure Write (Output : in out Staged_File; Data : Byte_Array) is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
      First  : Natural := Data'First;
   begin
      while First <= Data'Last loop
         declare
            Count : constant Natural := Natural'Min (Chunk_Size, Data'Last - First + 1);
         begin
            for K in 0 .. Count - 1 loop
               Buffer (Ada.Streams.Stream_Element_Offset (K + 1)) :=
                 Ada.Streams.Stream_Element (Data (First + K));
            end loop;
            Write (Output, Buffer (1 .. Ada.Streams.Stream_Element_Offset (Count)));
            exit when Data'Last - First < Count;
            First := First + Count;
         end;
      end loop;
   end Write;

   procedure Commit (Output : in out Staged_File) is
   begin
      if not Output.Active then
         raise Output_Failed with "no output in progress";
      end if;
      --  GNAT's Close frees the file before it raises Device_Error for a
      --  buffered write fclose could not flush, so Is_Open is False either way.
      SIO.Close (Output.File);
      Zlib.Native_Files.Replace (US.To_String (Output.Temp), US.To_String (Output.Target));
      Output.Active := False;
   exception
      when Output_Failed =>
         raise;
      when Storage_Error =>
         Discard (Output);
         raise;
      when others =>
         Discard (Output);
         raise Output_Failed with "cannot complete " & US.To_String (Output.Target);
   end Commit;

   procedure Discard (Output : in out Staged_File) is
   begin
      if SIO.Is_Open (Output.File) then
         begin
            SIO.Close (Output.File);
         exception
            when others =>
               null;
         end;
      end if;

      if Output.Active then
         Output.Active := False;
         declare
            Temp : constant String := US.To_String (Output.Temp);
         begin
            if Zlib.Native_Files.Kind (Temp) = Zlib.Native_Files.Ordinary_File then
               Zlib.Native_Files.Delete_File (Temp);
            end if;
         end;
      end if;
   exception
      when others =>
         null;
   end Discard;

   overriding procedure Finalize (Output : in out Staged_File) is
   begin
      Discard (Output);
   end Finalize;

end Zlib.Staged_Output;
