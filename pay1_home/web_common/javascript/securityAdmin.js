function results() {
  alert("Something unexpected occurred. Please contact support with error code SA-0x13342913.  Your request will proceed normally.");
}

function onlinehelp(subject) {
  helpURL = '/online_help/' + subject + '.html';
  helpWin = window.open(helpURL,'helpWin','menubar=no,status=no,scrollbars=yes,resizable=yes,width=350,height=350');
}

function help_win(helpurl,swidth,sheight) {
  SmallWin = window.open(helpurl,'HelpWindow','scrollbars=yes,resizable=yes,status=yes,toolbar=yes,menubar=yes,height='+sheight+',width='+swidth);
}

function close_me() {
  document.editUser.submit();
}

function popminifaq() {
  minifaq=window.open('/admin/wizards/faq_board.cgi?mode=mini_faq_list&category=all&search_keys=QA20050225215205,QA20011210184814','minifaq','width=600,height=400,toolbar=no,location=no,directories=no,status=yes,menubar=yes,scrollbars=yes,resizable=yes');
  if (window.focus) { minifaq.focus(); }
  return false;
}

function closewin() {
  self.close();
}

function ValidateArea(form) {
  var len = form.new_areas.length;
  var i = 0;
  var chosen = '';
  for (var i = 0; i < len; i++) {
    if (form.new_areas[i].selected) {
      chosen = chosen + form.new_areas[i].value + "\\n";
    }
  }
  if (chosen == '') {
    alert("You must assign the user to one or more Areas.");
    return false;
  }
  return true;
}

// Validate if user filled in API Key add form properly
function ValidateApiKeyAddForm() {
  if ((!document.getElementById('apikey_random').checked) && (document.getElementById('apikey_keyName').value == '')) { // if random unchecked & no keyname specified
    alert('Please specify an API Key name.');
    return false; // block submit
  }
  return true; // allow submit
};

// Push field value to end-user's clipboard
function copyFieldValue(e, id) {
  // Works In: IE9+, Firefox 41+, and Chrome 42+.
  var field = document.getElementById(id);
  field.focus();
  field.setSelectionRange(0, field.value.length);
  var copysuccess = copySelectionText();
  if (copysuccess) {
    alert('Added Text To Clipboard');
  }
}

function copySelectionText() {
  var copysuccess // var to check whether execCommand successfully executed
  try {
    copysuccess = document.execCommand('copy'); // run command to copy selected text to clipboard
  }
  catch(e) {
    copysuccess = false;
  }
  return copysuccess;
}

// Pop-up & populate apikey confirm form
function apikey_confirm(fnc, nme, rev) {
  $('#apikey_confirm_function').val( fnc );
  $('#apikey_confirm_keyName').val( nme );
  $('#apikey_confirm_revision').val( rev );

  var msg = 'Please confirm your request to continue?';
  if (fnc == 'expire_apikey') { msg = 'This will expire the API key selected. Do you wish to continue?'; }
  else if (fnc == 'reactivate_apikey') { msg = 'This will reactivate the API key selected. Do you wish to continue?'; }
  else if (fnc == 'delete_single_apikey') { msg = 'This will delete the API key selected & their related revisions. Do you wish to continue?'; }
  else if (fnc == 'add_apikey') { msg = 'This will expire the current API key revision & activate a new revision. Do you wish to continue?'; }
  $('#confirm_msg').html( msg );
}

// Ensure captcha is required in apikey confirm form
function apikey_confirm_submit() {
  var recaptcha = document.forms['apikey_confirm_form']['g-recaptcha-response'].value;
  //var $recaptcha = document.querySelector('#g-recaptcha-response');
  if (recaptcha) {
    return true;
  }
  alert('Please complete the CAPTCHA.');
  return false;
}

