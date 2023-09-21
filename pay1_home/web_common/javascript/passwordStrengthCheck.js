function passwordStrengthCheck() {
	var oldPasswordField = jQuery('input[name=oldpasswrd]') //current password field
	var newPasswordField = jQuery('input[name=passwrd1]') //first password field
	var passwordConfirmationField = jQuery('input[name=passwrd2]') //second password field
	var passwordStrengthDiv = jQuery('#passStrength');
	var passwordMatchDiv = jQuery('#passMatch')

	var username = jQuery('input[name=login]')
	var strengthPass = false
	var matchPass = false
	var fieldValuePass = false
	var passwordStrengthDivDisplayed = false

	//Bad:
	// Has Lowercase
	var hasLowercase = /[a-z]/
	// Has Uppercase
	var hasUppercase = /[A-Z]/
	// Has Number
	var hasNumber = /[0-9]/

	fadeInPasswordStrengthDiv = function() {
		if (passwordStrengthDivDisplayed != true) {
			passwordStrengthDivDisplayed = true
			passwordStrengthDiv.fadeIn('slow')
		}
	}

	fadeOutPasswordStrengthDiv = function() {
		if (passwordStrengthDivDisplayed != false) {
			passwordStrengthDivDisplayed = false
			passwordStrengthDiv.fadeOut('slow')
		}
	}

	jQuery(passwordConfirmationField).on('keyup', function(e) {
		passwordMatchDiv.fadeIn('slow')
	});

	function checkPasswordFields() {
	// Vastly simplified, increased minimum to 12 characters
		strengthPass = true

		passwordStrengthDiv.html("");

		// the following three checks are against "instance" variables"
		if (newPasswordField === undefined) {
			console.log('password1 is undefined')
			return
		}

		if (passwordConfirmationField === undefined) {
			console.log('password2 is undefined')
			return
		}

		if (username === undefined) {
			console.log("username is undefined")
			return
		}

		var newPassword = newPasswordField.val()
		var passwordConfirmation = passwordConfirmationField.val()
		var oldPassword = ""
		if (oldPasswordField != undefined) {
			oldPassword = oldPasswordField.val()
		}

		// Make sure bad things are not present
		//Cannot contain username
		if (newPassword.indexOf(username) > -1) {
			passwordStrengthDiv.addClass('weakpass').html("May not contain your login name<span id='image'></span><br>")
			strengthPass = strengthPass && false
		}

		//Cannot contain more than 3 consecutive characters that are in old password 
		if (oldPasswordField != undefined && oldPassword != "" && containsMatchingSubstrings(oldPassword,newPassword,3)) { 
			passwordStrengthDiv.addClass('weakpass').append("May not contain more than 3 consecutive characters that are in your current password.<span id='image'></span><br>")
			strengthPass = strengthPass && false
		}

		if (!hasNumber.test(newPassword)) {
			passwordStrengthDiv.addClass('weakpass').append("Must contain at least 1 number.<span id='image'></span><br>")
			strengthPass = strengthPass && false
		}

		if (!hasUppercase.test(newPassword)) {
			passwordStrengthDiv.addClass('weakpass').append("Must contain at least 1 UPPERCASE letter.<span id='image'></span><br>")
			strengthPass = strengthPass && false
		}

		if (!hasLowercase.test(newPassword)) {
			passwordStrengthDiv.addClass('weakpass').append("Must contain at least 1 lowercase letter.<span id='image'></span><br>")
			strengthPass = strengthPass && false
    }

		if (newPassword.length < 12) {
			passwordStrengthDiv.addClass('weakpass').append("Must be at least 12 characters<span id='image'></span><br>")
			strengthPass = strengthPass && false
		}

		if (strengthPass) {
			fadeOutPasswordStrengthDiv()
			passwordStrengthDiv.removeClass()
		} else {
			fadeInPasswordStrengthDiv()
		}

		// Make sure passwords match	
		if(newPassword !== passwordConfirmation) {
			passwordMatchDiv.removeClass().addClass('weakpass').html("Passwords do not match!<span id='image'></span>");
			matchPass = false
		}
		else {
			passwordMatchDiv.removeClass().addClass('goodpass').html("Passwords match!<span id='image'></span>");
			matchPass = true
		}

		// enable submit button if strength and match pass
		if (strengthPass && matchPass) {
			jQuery('#passwordSubmitButton').removeAttr("disabled")
			jQuery('#passwordSubmitButton').css('opacity','1')
		}
		else {
			jQuery('#passwordSubmitButton').attr("disabled", "disabled")
			jQuery('#passwordSubmitButton').css('opacity','0.3')
		}
	};

	jQuery('.passwordCheck').on('keyup', checkPasswordFields)


	// Make sure fields are not empty and validate current password on click
	jQuery('#passwordSubmitButton').click(function() {
		jQuery('#emptyField').html("Please Wait...")
		//empty field check
		jQuery('.passwordCheck').each(function( index ) {
			if (jQuery(this).val() == '') {
				jQuery(this).css("background-color","#FDD")
				jQuery(this).focus()
				jQuery('#emptyField').html("Missing Required Field")
				return false
				}
			else {
				fieldValuePass = true
			}
		});
		//other checks
		if (fieldValuePass == true) {
			//For password change form
			if (oldPasswordField.val() !== undefined) { //field exists
				// make sure current password is correct
				jQuery.post('/admin/security/_json/passwordcheck.cgi', { password: oldPasswordField.val() },function(data,status){
					if (data['verified'] == 0) {
						jQuery('#emptyField').html("Current Password does not match what is on file.");
						return false
					}
				});
			}
			//For add sub-user form
			else if (jQuery('select[name=new_areas]').val() !== undefined) { //field exists
				// make sure section is selected
				if (jQuery('select[name=new_areas] option:selected').text() == "") {
					jQuery('select[name=new_areas]').css("background-color","#FDD")
					jQuery('#emptyField').html("Please select at least one area")
					return false
				}
			}
			
			// base case
			jQuery('form').submit()
		}
	});
}


function containsMatchingSubstrings(string1,string2, substringLength) {
	if ((string1 != undefined) && (string2 != undefined) && (substringLength != undefined)) {
		// convert to lowercase
		string1 = string1.toLowerCase()
		string2 = string2.toLowerCase()

		if (string2.length >= substringLength) {
			for (var i = 0; i < (string1.length - (substringLength - 1)); i++) {
				var substring = string1.substr(i,substringLength)
				if (string2.indexOf(substring) > -1) {
					return true
				}
			}
		}
		//substring of old password was not found in new password
  		return false
	}
}
