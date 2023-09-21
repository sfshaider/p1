/*
	This is similar to the z_checkbox, but (obviously) used for radio inputs
	Usage: jQuery('selector').z_radio('FA image class'); 
		--The Font Awesome (FA) image class is optional. If left unset will then image defaults
		to using a plain check.
	
		--This automatically calls $.change() when the radio is changed, so all functionality
		MUST be set off that.

*/

jQuery.fn.z_radio = function (icon) {
	return this.each(function() {
		var radio = this;
		var checkSpan = '<i class="z_radio_hidden">&#x2713;</i>';
		if (icon != null && icon != "") {
			checkSpan = '<i class= "fa ' + icon + ' z_radio_hidden"></i>';
   		}
		
		if (jQuery(this).parent().is('span') && jQuery(this).parent().find('.z_raido_button').length >= 1) { return;}
		jQuery(this).addClass('z_radio_hidden')
		.wrap('<span>')
		.after('<span class="z_radio_button"><span class="z_radio">' + checkSpan +'</span></span>')
   		.parent().on('click', function() {
			jQuery('span.z_radio_active').toggleClass('z_radio_active').find('i').toggleClass('z_radio_hidden').toggleClass('z_radio_checked');
			jQuery('input[name=' + radio.name + '][value="' + jQuery(radio).val() + '"]').prop('checked',true).change();
			jQuery(this).toggleClass('z_radio_active');
			jQuery(this).find('i').toggleClass('z_radio_hidden');
			return false;
		});


		jQuery(this).on('click', function() {
			jQuery(this).parent().find('span.z_radio_button').click();
			return false;
		});
		if (jQuery(radio).prop('checked')) {
			jQuery(radio).parent().addClass('z_radio_active').find('i').removeClass('z_radio_hidden').addClass('z_radio_checked');;
		}
		jQuery(this).on('change',function() {
                        if (jQuery(radio).is(':checked')) {
                                jQuery(radio).parent().find('i').removeClass('z_check_hidden').addClass('z_radio_checked');
                        } else {
                                jQuery(radio).parent().find('i').addClass('z_check_hidden').removeClass('z_radio_Checked');
                        }
                });
		
	});
};

jQuery.fn.un_z_radio = function() {
  return this.each(function() {
	var theReadRadio = jQuery(this).find('input[type=radio]');
	jQuery(this).replaceWith(theRealRadio);
	jQuery(theRealRadio).removeClass('z_radio_hidden');
  });
};
