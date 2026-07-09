with Ada.Strings.Unbounded;
with Interfaces;
with Zlib.Seven_Zip_Container;
with Zlib.Seven_Zip_Header_Reading;
with Zlib.Seven_Zip_Methods; use Zlib.Seven_Zip_Methods;
with Zlib.Seven_Zip_Numbers;
with Zlib.Seven_Zip_Properties;

package body Zlib.Seven_Zip_Listing is
   package US renames Ada.Strings.Unbounded;

   use type Interfaces.Unsigned_64;

   subtype Seven_Zip_LZMA_Props is Byte_Array (1 .. 5);

   function List
     (Archive_Image              : Byte_Array;
      Password                   : String;
      Decode_LZMA_Encoded_Header : not null access function
        (Input         : Byte_Array;
         LZMA_Props    : Byte_Array;
         Expected_Size : Natural;
         Status        : out Status_Code) return Byte_Array;
      Status                     : out Status_Code) return Archive_Entry_Array
   is
      No : constant Archive_Entry_Array (1 .. 0) :=
        [others => (others => <>)];
      No_Bytes : constant Byte_Array (1 .. 0) := [others => 0];

      --  Decode the next-header bytes into a plain (kHeader 0x01) image.
      function Plain_Header return Byte_Array is
         Base : constant Natural := Archive_Image'First + 32;
         NHO  : constant Natural :=
           Natural (Zlib.Seven_Zip_Numbers.U64_At (Archive_Image, Archive_Image'First + 12));
         NHS  : constant Natural :=
           Natural (Zlib.Seven_Zip_Numbers.U64_At (Archive_Image, Archive_Image'First + 20));

         function Decode_Header_Payload
           (Input          : Byte_Array;
            Method         : Seven_Zip_Coder_Method;
            LZMA_Props     : Byte_Array;
            Expected_Size  : Natural;
            Delta_Distance : Positive;
            PPMd_Order     : Natural;
            PPMd_Memory    : Interfaces.Unsigned_32;
            Decode_Status  : out Status_Code) return Byte_Array
         is
            pragma Unreferenced (Delta_Distance, PPMd_Order, PPMd_Memory);
            Props : Seven_Zip_LZMA_Props := [others => 0];
         begin
            case Method is
               when Seven_Zip_Copy =>
                  Decode_Status := Ok;
                  return Input;

               when Seven_Zip_LZMA_Method =>
                  if LZMA_Props'Length /= Props'Length then
                     Decode_Status := Unsupported_Method;
                     return No_Bytes;
                  end if;

                  for Offset in 0 .. Props'Length - 1 loop
                     Props (Props'First + Offset) :=
                       LZMA_Props (LZMA_Props'First + Offset);
                  end loop;

                  return Decode_LZMA_Encoded_Header
                    (Input, Props, Expected_Size, Decode_Status);

               when others =>
                  Decode_Status := Unsupported_Method;
                  return No_Bytes;
            end case;
         end Decode_Header_Payload;
      begin
         if NHS = 0 or else Base + NHO + NHS - 1 > Archive_Image'Last then
            return No_Bytes;
         end if;

         declare
            H : constant Byte_Array :=
              Archive_Image (Base + NHO .. Base + NHO + NHS - 1);
         begin
            if H (H'First) = 16#01# then
               return H;
            elsif H (H'First) /= 16#17# then
               return No_Bytes;
            end if;
         end;

         declare
            Info : constant Zlib.Seven_Zip_Container.Start_Header_Info :=
              (Payload_First => Base,
               Header_First  => Base + NHO,
               Header_Last   => Base + NHO + NHS - 1,
               Payload_Count => NHO,
               Header_Count  => NHS,
               Header_CRC    => 0);
            Header_Status : Status_Code := Ok;
            Pack_Pos      : Natural := 0;
            Header        : constant Byte_Array :=
              Zlib.Seven_Zip_Header_Reading.Decode_Encoded_Header
                (Archive_Image, Password, Info, Decode_Header_Payload'Access,
                 Pack_Pos, Header_Status);
         begin
            if Header_Status /= Ok
              or else Header'Length = 0
              or else Header (Header'First) /= 16#01#
            then
               return No_Bytes;
            end if;

            return Header;
         end;
      end Plain_Header;

      Header : constant Byte_Array := Plain_Header;
   begin
      Status := Unsupported_Method;
      if Archive_Image'Length < 32
        or else Archive_Image (Archive_Image'First) /= 16#37#
        or else Archive_Image (Archive_Image'First + 1) /= 16#7A#
      then
         Status := Invalid_Header;
         return No;
      end if;
      if Header'Length = 0 or else Header (Header'First) /= 16#01# then
         Status := Unsupported_Method;
         return No;
      end if;

      declare
         P : Natural := Header'First + 1;

         Max_Sub : constant Natural := 4096;
         Sub_Size : array (1 .. Max_Sub) of Interfaces.Unsigned_64 :=
           [others => 0];
         Sub_CRC  : array (1 .. Max_Sub) of Interfaces.Unsigned_32 :=
           [others => 0];
         Sub_Count : Natural := 0;

         Max_Fold : constant Natural := 4096;
         Folder_Size  : array (1 .. Max_Fold) of Interfaces.Unsigned_64 :=
           [others => 0];
         Num_Folders : Natural := 0;

         procedure Skip_Number is
            Dummy : Interfaces.Unsigned_64 := 0;
            Ok_N  : constant Boolean :=
              Zlib.Seven_Zip_Numbers.Read_Number (Header, P, Header'Last, Dummy);
         begin
            if not Ok_N then
               raise Constraint_Error;
            end if;
         end Skip_Number;

         function Num return Interfaces.Unsigned_64 is
            R : Interfaces.Unsigned_64 := 0;
         begin
            if not Zlib.Seven_Zip_Numbers.Read_Number (Header, P, Header'Last, R) then
               raise Constraint_Error;
            end if;
            return R;
         end Num;
      begin
         if P <= Header'Last and then Header (P) = 16#04# then
            P := P + 1;
            if P <= Header'Last and then Header (P) = 16#06# then
               P := P + 1;
               Skip_Number;
               declare
                  NP : constant Natural := Natural (Num);
               begin
                  loop
                     exit when P > Header'Last or else Header (P) = 0;
                     if Header (P) = 16#09# then
                        P := P + 1;
                        for K in 1 .. NP loop
                           Skip_Number;
                        end loop;
                     elsif Header (P) = 16#0A# then
                        P := P + 1;
                        declare
                           All_Def : constant Byte := Header (P);
                        begin
                           P := P + 1;
                           for K in 1 .. NP loop
                              if All_Def /= 0 then
                                 P := P + 4;
                              end if;
                           end loop;
                        end;
                     else
                        exit;
                     end if;
                  end loop;
               end;
               if P <= Header'Last and then Header (P) = 0 then
                  P := P + 1;
               end if;
            end if;

            if P <= Header'Last and then Header (P) = 16#07# then
               P := P + 1;
               if P <= Header'Last and then Header (P) = 16#0B# then
                  P := P + 1;
                  Num_Folders := Natural (Num);
                  declare
                     External : constant Byte := Header (P);
                  begin
                     P := P + 1;
                     if External /= 0 then
                        Status := Unsupported_Method;
                        return No;
                     end if;
                  end;
                  declare
                     Out_Per : array (1 .. Max_Fold) of Natural :=
                       [others => 1];
                  begin
                     for F in 1 .. Num_Folders loop
                        declare
                           NC : constant Natural := Natural (Num);
                           Tot_In, Tot_Out : Natural := 0;
                        begin
                           for C in 1 .. NC loop
                              declare
                                 Flag : constant Byte := Header (P);
                                 ID_Sz : constant Natural :=
                                   Natural (Flag and 16#0F#);
                              begin
                                 P := P + 1 + ID_Sz;
                                 if (Flag and 16#10#) /= 0 then
                                    Tot_In := Tot_In + Natural (Num);
                                    Tot_Out := Tot_Out + Natural (Num);
                                 else
                                    Tot_In := Tot_In + 1;
                                    Tot_Out := Tot_Out + 1;
                                 end if;
                                 if (Flag and 16#20#) /= 0 then
                                    declare
                                       PS : constant Natural := Natural (Num);
                                    begin
                                       P := P + PS;
                                    end;
                                 end if;
                              end;
                           end loop;
                           if F <= Max_Fold then
                              Out_Per (F) := Tot_Out;
                           end if;
                           for K in 1 .. Tot_Out - 1 loop
                              Skip_Number;
                              Skip_Number;
                           end loop;
                           declare
                              NPacked : constant Natural :=
                                Tot_In - (Tot_Out - 1);
                           begin
                              if NPacked > 1 then
                                 for K in 1 .. NPacked loop
                                    Skip_Number;
                                 end loop;
                              end if;
                           end;
                        end;
                     end loop;
                     if not Zlib.Seven_Zip_Container.Expect_Byte
                       (Header, P, Header'Last, 16#0C#)
                     then
                        Status := Unsupported_Method;
                        return No;
                     end if;
                     for F in 1 .. Num_Folders loop
                        declare
                           Last_Size : Interfaces.Unsigned_64 := 0;
                        begin
                           for K in 1 .. Out_Per (F) loop
                              Last_Size := Num;
                           end loop;
                           if F <= Max_Fold then
                              Folder_Size (F) := Last_Size;
                           end if;
                        end;
                     end loop;
                  end;
                  if P <= Header'Last and then Header (P) = 16#0A# then
                     P := P + 1;
                     declare
                        All_Def : constant Byte := Header (P);
                     begin
                        P := P + 1;
                        for F in 1 .. Num_Folders loop
                           if All_Def /= 0 then
                              pragma Unreferenced (F);
                              P := P + 4;
                           end if;
                        end loop;
                     end;
                  end if;
                  if P <= Header'Last and then Header (P) = 0 then
                     P := P + 1;
                  end if;
               end if;
            end if;

            declare
               Streams_Per : array (1 .. Max_Fold) of Natural :=
                 [others => 1];
            begin
               if P <= Header'Last and then Header (P) = 16#08# then
                  P := P + 1;
                  if P <= Header'Last and then Header (P) = 16#0D# then
                     P := P + 1;
                     for F in 1 .. Num_Folders loop
                        Streams_Per (F) := Natural (Num);
                     end loop;
                  end if;
                  if P <= Header'Last and then Header (P) = 16#09# then
                     P := P + 1;
                     for F in 1 .. Num_Folders loop
                        declare
                           Sum : Interfaces.Unsigned_64 := 0;
                        begin
                           for K in 1 .. Streams_Per (F) - 1 loop
                              declare
                                 S : constant Interfaces.Unsigned_64 := Num;
                              begin
                                 Sum := Sum + S;
                                 Sub_Count := Sub_Count + 1;
                                 if Sub_Count <= Max_Sub then
                                    Sub_Size (Sub_Count) := S;
                                 end if;
                              end;
                           end loop;
                           Sub_Count := Sub_Count + 1;
                           if Sub_Count <= Max_Sub then
                              Sub_Size (Sub_Count) :=
                                (if Folder_Size (F) >= Sum
                                 then Folder_Size (F) - Sum else 0);
                           end if;
                        end;
                     end loop;
                  else
                     for F in 1 .. Num_Folders loop
                        for K in 1 .. Streams_Per (F) loop
                           Sub_Count := Sub_Count + 1;
                           if Sub_Count <= Max_Sub and then K = 1 then
                              Sub_Size (Sub_Count) := Folder_Size (F);
                           end if;
                        end loop;
                     end loop;
                  end if;
                  if P <= Header'Last and then Header (P) = 16#0A# then
                     P := P + 1;
                     declare
                        All_Def : constant Byte := Header (P);
                     begin
                        P := P + 1;
                        for I in 1 .. Sub_Count loop
                           if All_Def /= 0 then
                              if Zlib.Seven_Zip_Container.Has_Bytes (P, Header'Last, 4) then
                                 Sub_CRC (I) :=
                                   Zlib.Seven_Zip_Numbers.U32_At (Header, P);
                                 P := P + 4;
                              end if;
                           end if;
                        end loop;
                     end;
                  end if;
                  while P <= Header'Last and then Header (P) /= 0 loop
                     P := P + 1;
                  end loop;
                  if P <= Header'Last then
                     P := P + 1;
                  end if;
               else
                  for F in 1 .. Num_Folders loop
                     Sub_Count := Sub_Count + 1;
                     if Sub_Count <= Max_Sub then
                        Sub_Size (Sub_Count) := Folder_Size (F);
                     end if;
                  end loop;
               end if;
            end;

            if P <= Header'Last and then Header (P) = 0 then
               P := P + 1;
            end if;
         end if;

         if P > Header'Last or else Header (P) /= 16#05# then
            Status := Unsupported_Method;
            return No;
         end if;
         P := P + 1;
         declare
            File_Count : constant Natural := Natural (Num);
            Has_Stream : array (1 .. Natural'Max (File_Count, 1)) of Boolean :=
              [others => True];
            Is_Dir     : array (1 .. Natural'Max (File_Count, 1)) of Boolean :=
              [others => False];
            Names      : array (1 .. Natural'Max (File_Count, 1)) of
              US.Unbounded_String := [others => US.Null_Unbounded_String];
            Empty_Seen : Natural := 0;
         begin
            if File_Count = 0 or else File_Count > Max_Sub then
               Status := Unsupported_Method;
               return No;
            end if;
            loop
               exit when P > Header'Last or else Header (P) = 0;
               declare
                  Prop_Id   : constant Byte := Header (P);
                  Prop_Size : Interfaces.Unsigned_64 := 0;
               begin
                  P := P + 1;
                  if not Zlib.Seven_Zip_Numbers.Read_Number
                    (Header, P, Header'Last, Prop_Size)
                  then
                     Status := Unsupported_Method;
                     return No;
                  end if;
                  declare
                     Prop_First : constant Natural := P;
                     Prop_Last  : constant Natural :=
                       P + Natural (Prop_Size) - 1;
                  begin
                     if Prop_Last > Header'Last then
                        Status := Unsupported_Method;
                        return No;
                     end if;
                     case Prop_Id is
                        when 16#0E# =>
                           for I in 1 .. File_Count loop
                              if Zlib.Seven_Zip_Properties.Bit_Is_Set
                                (Header, Prop_First, I)
                              then
                                 Has_Stream (I) := False;
                                 Is_Dir (I) := True;
                              end if;
                           end loop;
                        when 16#0F# =>
                           Empty_Seen := 0;
                           for I in 1 .. File_Count loop
                              if not Has_Stream (I) then
                                 Empty_Seen := Empty_Seen + 1;
                                 if Zlib.Seven_Zip_Properties.Bit_Is_Set
                                   (Header, Prop_First, Empty_Seen)
                                 then
                                    Is_Dir (I) := False;
                                 end if;
                              end if;
                           end loop;
                        when 16#11# =>
                           declare
                              NP : Natural := Prop_First + 1;
                              FI : Natural := 1;
                           begin
                              while NP + 1 <= Prop_Last and then FI <= File_Count loop
                                 declare
                                    S : US.Unbounded_String :=
                                      US.Null_Unbounded_String;
                                 begin
                                    while NP + 1 <= Prop_Last
                                      and then not (Header (NP) = 0
                                                    and then Header (NP + 1) = 0)
                                    loop
                                       US.Append
                                         (S,
                                          Character'Val
                                            (Natural (Header (NP)) +
                                             Natural (Header (NP + 1)) * 256));
                                       NP := NP + 2;
                                    end loop;
                                    Names (FI) := S;
                                    NP := NP + 2;
                                    FI := FI + 1;
                                 end;
                              end loop;
                           end;
                        when others =>
                           null;
                     end case;
                     P := Prop_Last + 1;
                  end;
               end;
            end loop;

            return Result : Archive_Entry_Array (1 .. File_Count) do
               declare
                  Sub_Idx : Natural := 0;
               begin
                  for I in 1 .. File_Count loop
                     declare
                        USz : Interfaces.Unsigned_64 := 0;
                        Crc : Interfaces.Unsigned_32 := 0;
                     begin
                        if Has_Stream (I) then
                           Sub_Idx := Sub_Idx + 1;
                           if Sub_Idx <= Sub_Count then
                              USz := Sub_Size (Sub_Idx);
                              Crc := Sub_CRC (Sub_Idx);
                           end if;
                        end if;
                        Result (I) :=
                          (Name              => Names (I),
                           Is_Directory      => Is_Dir (I),
                           Compression       => 0,
                           Uncompressed_Size => USz,
                           Compressed_Size   => 0,
                           CRC_32            => Crc);
                     end;
                  end loop;
                  Status := Ok;
               end;
            end return;
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return No;
   end List;

end Zlib.Seven_Zip_Listing;
