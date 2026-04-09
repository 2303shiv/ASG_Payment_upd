CLASS zcl_customer_invoice_posting DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_bill_details,
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
           END OF ty_bill_details.

    TYPES : tt_bill_details TYPE STANDARD TABLE OF ty_bill_details WITH DEFAULT KEY..
    DATA :  lt_bill_output      TYPE tt_bill_details.
    DATA :  lt_bill_final      TYPE tt_bill_details.


*-- Create Table to Populate data which we are using while calling RAP BO.

    DATA: lt_entry              TYPE TABLE FOR ACTION IMPORT i_journalentrytp~post,
          ls_entry              LIKE LINE OF lt_entry,
          ls_glitem             LIKE LINE OF ls_entry-%param-_glitems,
          ls_aritem             LIKE LINE OF ls_entry-%param-_aritems,
          ls_apitem             LIKE LINE OF ls_entry-%param-_apitems,
          ls_tax                LIKE LINE OF ls_entry-%param-_taxitems,
          ls_tax_withholding    LIKE LINE OF ls_entry-%param-_withholdingtaxitems,
          ls_amount             LIKE LINE OF ls_glitem-_currencyamount,
          ls_tax_amt            LIKE LINE OF ls_tax-_currencyamount,
          ls_tax_witholding_amt LIKE LINE OF ls_tax_withholding-_currencyamount,
          out                   TYPE REF TO  if_oo_adt_classrun_out,
          lv_cid                TYPE         abp_behv_cid,
          lv_error              TYPE         string,
          lv_date               TYPE         sy-datum,
          lv_fiscal_year        TYPE         char4,
          lv_fiscal_period      TYPE         char3,
          lv_total_amount       TYPE          p DECIMALS 2,
*          lt_count              TYPE         TABLE OF zdb_bill_hos_log,
          lv_no                 TYPE         numc5.

    CONSTANTS: lv_val TYPE char6  VALUE '000001',
               lv_msg TYPE char100 VALUE 'Document created Sucessfully'.


    METHODS constructor
      IMPORTING
        lt_bill_output TYPE tt_bill_details.

    INTERFACES if_serializable_object .
    INTERFACES if_abap_parallel .


  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_CUSTOMER_INVOICE_POSTING IMPLEMENTATION.


  METHOD constructor.
    lt_bill_final = lt_bill_output.
  ENDMETHOD.


  METHOD if_abap_parallel~do.
    SELECT SINGLE fiscalyear, fiscalperiod
            FROM i_fisccalendardateforcompcode
            WHERE calendardate = @sy-datum"@lv_date
            INTO (@lv_fiscal_year, @lv_fiscal_period).

    DATA: ls_bill_netram TYPE zdb_bill_hos_log .

    DELETE lt_bill_final INDEX 1.
    DATA(lt_bill_header) = lt_bill_final.
    DELETE ADJACENT DUPLICATES FROM lt_bill_header COMPARING refrence_no.

    LOOP AT lt_bill_header INTO DATA(ls_bill_header).

      CLEAR lv_cid.
      TRY.
          lv_cid = to_upper( cl_uuid_factory=>create_system_uuid( )->create_uuid_x16( ) ).
        CATCH cx_uuid_error.
          ASSERT 1 = 0.
      ENDTRY.
      CLEAR: ls_entry, ls_glitem, ls_aritem, ls_tax, ls_tax_withholding, ls_amount, ls_tax_amt, ls_tax_witholding_amt.
      "Fill Header details

      ls_entry = VALUE #(
        %cid                          = lv_cid
        %param                        = VALUE #(
          companycode                 = ls_bill_header-company_code
          businesstransactiontype     = 'RFBU'
          accountingdocumenttype      = ls_bill_header-journal_entry_type
          postingfiscalperiod         = lv_fiscal_period+1(2)
          taxdeterminationdate        = ls_bill_header-journal_entry_date
          documentdate                = ls_bill_header-journal_entry_date
          postingdate                 = ls_bill_header-posting_date
          accountingdocumentheadertext = ls_bill_header-header_text
          createdbyuser               = sy-uname
        )
      ).
      "Fill GL Item details
      lv_no = '000001'.  " Unique item number
      IF ls_bill_header-journal_entry_type = 'DZ'. " Customer Invoice
        CLEAR ls_aritem.
      ls_aritem = VALUE #(
      glaccountlineitem             = lv_no
      customer                      = ls_bill_header-customer_no
      assignmentreference            = ls_bill_header-refrence_no
  ).

        ls_amount = VALUE #(
        currencyrole              = '00'          " Transaction Currency
        currency                  = 'INR'
        journalentryitemamount    = ls_bill_header-amount
      ).
        APPEND ls_amount TO ls_aritem-_currencyamount.
        APPEND ls_aritem TO ls_entry-%param-_aritems.
      ELSEIF ls_bill_header-journal_entry_type = 'KZ'. " Vendor Invoice
        CLEAR ls_apitem.
        ls_apitem = VALUE #(
        glaccountlineitem             = lv_no
        supplier                      = ls_bill_header-customer_no
        assignmentreference            = ls_bill_header-refrence_no
).
        ls_amount = VALUE #(
        currencyrole              = '00'          " Transaction Currency
        currency                  = 'INR'
        journalentryitemamount    = ls_bill_header-amount
      ).
        APPEND ls_amount TO ls_apitem-_currencyamount.
        APPEND ls_apitem TO ls_entry-%param-_apitems.
      ENDIF.

      LOOP AT lt_bill_final ASSIGNING FIELD-SYMBOL(<fs_bill_final>) WHERE refrence_no = ls_bill_header-refrence_no.
        IF <fs_bill_final>-gl_account IS NOT INITIAL.
          CLEAR ls_glitem.
          lv_no = lv_no + 1.
          ls_glitem = VALUE #(
            glaccountlineitem             = lv_no
            glaccount                     = <fs_bill_final>-gl_account
            profitcenter                  = <fs_bill_final>-profit_center
            housebank                     = <fs_bill_final>-house_bank
            housebankaccount              = <fs_bill_final>-house_bank_id
          ).

          ls_amount = VALUE #(
            currencyrole              = '00'          " Transaction Currency
            currency                  = 'INR'
            journalentryitemamount    = <fs_bill_final>-amount * -1
          ).
          APPEND ls_amount TO ls_glitem-_currencyamount.
          APPEND ls_glitem TO ls_entry-%param-_glitems.
        ENDIF.

      ENDLOOP.
      APPEND ls_entry TO lt_entry.

      IF lt_entry IS NOT INITIAL.

        MODIFY ENTITIES OF i_journalentrytp
        ENTITY journalentry
        EXECUTE post FROM lt_entry
        FAILED   DATA(ls_post_failed)
        REPORTED DATA(ls_post_reported)
        MAPPED   DATA(ls_post_mapped).
        IF ls_post_failed IS NOT INITIAL.
          lv_error = REDUCE string(
                   INIT result = ``
                   FOR ls_report_temp IN ls_post_reported-journalentry
                   NEXT result = result && | { ls_report_temp-%msg->if_message~get_text( ) }|
                 ).
        ELSE.

          COMMIT ENTITIES BEGIN
          RESPONSE OF i_journalentrytp
          FAILED DATA(lt_commit_failed)
          REPORTED DATA(lt_commit_reported).
          ...
          COMMIT ENTITIES END.
        ENDIF.
      ENDIF.
      CLEAR : lv_no, lt_entry,ls_post_mapped,ls_post_reported,ls_post_failed,lt_commit_reported,lt_commit_failed.
    ENDLOOP.

  ENDMETHOD.
ENDCLASS.
