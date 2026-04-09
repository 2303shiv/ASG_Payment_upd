CLASS lhc_zi_mass_customer_posting_u DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR zi_mass_customer_posting_upd RESULT result.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR zi_mass_customer_posting_upd RESULT result.

    METHODS earlynumbering_create FOR NUMBERING
      IMPORTING entities FOR CREATE zi_mass_customer_posting_upd.

    METHODS processfile FOR MODIFY
      IMPORTING keys FOR ACTION zi_mass_customer_posting_upd~processfile RESULT result.

ENDCLASS.

CLASS lhc_zi_mass_customer_posting_u IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD get_global_authorizations.
  ENDMETHOD.

  METHOD earlynumbering_create.

    LOOP AT entities ASSIGNING FIELD-SYMBOL(<fs_entities>).

      APPEND CORRESPONDING #( <fs_entities> ) TO mapped-zi_mass_customer_posting_upd
      ASSIGNING FIELD-SYMBOL(<fs_xlhead>).
      <fs_xlhead>-enduser = cl_abap_context_info=>get_user_technical_name( ).
      IF <fs_xlhead>-fileid IS INITIAL.
        TRY.
            <fs_xlhead>-fileid = cl_system_uuid=>create_uuid_x16_static(  ).
          CATCH cx_uuid_error.
        ENDTRY.
      ENDIF.
    ENDLOOP.


  ENDMETHOD.

  METHOD processfile.

    DATA: lt_custinv TYPE cl_abap_parallel=>t_in_inst_tab .

    DATA lo_table_descr  TYPE REF TO cl_abap_tabledescr.
    DATA lo_struct_descr TYPE REF TO cl_abap_structdescr.

    TYPES: BEGIN OF ty_keys,

             company_code       TYPE c LENGTH 4,
             posting_date       TYPE d,
             journal_entry_date TYPE d,
             value_date         TYPE d,
             refrence_no        TYPE c LENGTH 20,
             journal_entry_type TYPE c LENGTH 4,
             header_text        TYPE c LENGTH 100,
             profit_center      TYPE c LENGTH 30,
             house_bank         TYPE c LENGTH 10,
             house_bank_id      TYPE c LENGTH 10,
             amount             TYPE c LENGTH 20,
             customer_no        TYPE c LENGTH 10,
             gl_account         TYPE c LENGTH 10,
           END OF ty_keys.

    TYPES : tt_new TYPE STANDARD TABLE OF ty_keys WITH DEFAULT KEY..
    DATA :     lt_new_keys  TYPE tt_new.

    " TODO: variable is assigned but never used (ABAP cleaner)
    DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).

    READ ENTITIES OF zi_mass_customer_posting_upd IN LOCAL MODE
         ENTITY zi_mass_customer_posting_upd ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_file_entity).

    " Get attachment value from the instance
    DATA(lv_attachment) = lt_file_entity[ 1 ]-attachment.
    DATA(lv_file) = lt_file_entity[ 1 ]-filename.
    IF lv_attachment IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lo_xlsx) = xco_cp_xlsx=>document->for_file_content( iv_file_content = lv_attachment )->read_access( ).

    DATA(lo_worksheet) = lo_xlsx->get_workbook( )->worksheet->at_position( 1 ).

    DATA(lo_selection_pattern) = xco_cp_xlsx_selection=>pattern_builder->simple_from_to( )->get_pattern( ).

    DATA(lo_execute) = lo_worksheet->select( lo_selection_pattern
      )->row_stream(
      )->operation->write_to( REF #( lt_new_keys ) ).

    lo_execute->set_value_transformation( xco_cp_xlsx_read_access=>value_transformation->string_value
               )->if_xco_xlsx_ra_operation~execute( ).

    SELECT SINGLE FROM zerror_log_grn
   FIELDS filename
   WHERE filename = @lv_file
   INTO @DATA(lv_file_name).

    IF sy-subrc <> 0.

*      LOOP AT lt_new_keys ASSIGNING FIELD-SYMBOL(<fs_key>).
*        <fs_key>-username = lv_user.
*        <fs_key>-filename = lv_file.
*      ENDLOOP.

*********************************Adding In Helper **************************************


      DATA(lo_proc) = NEW cl_abap_parallel( p_percentage = 30 )  .

      IF lt_new_keys IS NOT INITIAL .

        INSERT NEW zcl_customer_invoice_posting(  lt_bill_output = CORRESPONDING #( lt_new_keys )  )
        INTO TABLE lt_custinv.

        IF lt_custinv IS NOT INITIAL .

          lo_proc->run_inst(  EXPORTING p_in_tab = lt_custinv
                                       p_debug = abap_false
                              IMPORTING p_out_tab = DATA(lt_finished)  ).
        ENDIF.
      ENDIF.

      MODIFY ENTITIES OF zi_mass_customer_posting_upd IN LOCAL MODE
      ENTITY zi_mass_customer_posting_upd
      UPDATE FIELDS ( filestatus ) WITH VALUE #( FOR key IN keys ( %tky = key-%tky filestatus = 'S' ) ).
      result = VALUE #( FOR key IN keys ( %tky = key-%tky
      %param = CORRESPONDING #( key ) ) ) .

      APPEND VALUE #( %msg = new_message_with_text(
      severity = if_abap_behv_message=>severity-success
      text = 'File Uploaded Successfully' ) )
      TO reported-zi_mass_customer_posting_upd.

    ELSE.

      MODIFY ENTITIES OF zi_mass_customer_posting_upd IN LOCAL MODE
      ENTITY zi_mass_customer_posting_upd
      UPDATE FIELDS ( filestatus ) WITH VALUE #( FOR key IN keys ( %tky = key-%tky filestatus = 'F' ) ).
      result = VALUE #( FOR key IN keys ( %tky = key-%tky
      %param = CORRESPONDING #( key ) ) ) .

      APPEND VALUE #( %msg = new_message_with_text(
      severity = if_abap_behv_message=>severity-success
      text = 'File is already uploaded , upload different file' ) )
      TO reported-zi_mass_customer_posting_upd.
    ENDIF.


  ENDMETHOD.

ENDCLASS.
