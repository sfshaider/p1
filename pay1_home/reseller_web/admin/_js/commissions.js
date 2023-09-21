$(function() {
  $( "input[type=submit]" )
    .submit()
    .click(function( event ) {
      event.preventDefault();
      var $form = $(this.form);
      var submit_value = $form.serialize() + "&function=updatepaid";
      // disable all forms
      $("input[type=submit]").attr("disabled", "disabled");
      // submit to the script
      var posting = $.post("commission/data.cgi", submit_value);
      posting.done( function( data ) {
        var status = data.status;
        if (status=="1") {
          alert("Update was successful.");
          // hide the form
          $form.hide();
        } else {
          alert("Update failed.");
        }
      });
      // enable the forms again
      $("input[type=submit]").removeAttr("disabled");
    });
});
