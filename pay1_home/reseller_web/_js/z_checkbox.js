/*
Copyright 2013 Plug And Pay Technologies, Inc.
Written by C. Isomaki.
Version 0.1

Usage: jQuery('selector').z_checkbox(); // applies styled checkbox to checkbox
       Using .click() on the original checkbox to toggle the real checkbox will update the styled checkbox as well.
       Using .change() on the original checkbox will update the styled checkbox to match the same state.
*/

jQuery.fn.z_checkbox = function() {
	return this.each(function() {
		var checkbox = this;
		if (jQuery(this).parent().is('span') && jQuery(this).parent().find('.z_checkbox').length >= 1) { return; }
		jQuery(this).addClass('z_check_hidden')
 		.wrap('<span>')
		.after('<span class="z_checkbox"><span class="z_check z_check_hidden">&#x2713;</span></span>')
		.parent().find('span.z_checkbox').on('click',function() { 
			jQuery(this).toggleClass('z_checkbox_checked').find('span.z_check').toggleClass('z_check_hidden'); 
			jQuery(checkbox).prop('checked',!jQuery(checkbox).prop('checked')).change(); 
			return false;
		});
		jQuery(this).on('click',function() { 
			jQuery(this).parent().find('span.z_checkbox').click();
			return false;
		});
		jQuery(this).on('change',function() { 
			if (jQuery(checkbox).is(':checked')) { 
				jQuery(checkbox).parent().find('span.z_checkbox').addClass('z_checkbox_checked').find('span.z_check').removeClass('z_check_hidden'); 
			} else { 
				jQuery(checkbox).parent().find('span.z_checkbox').removeClass('z_checkbox_checked').find('span.z_check').addClass('z_check_hidden'); 
			} 
		}); 
		if (jQuery(checkbox).prop('checked')) { 
			jQuery(checkbox).parent().find('span.z_checkbox').addClass('z_checkbox_checked').find('span.z_check').removeClass('z_check_hidden'); 
		}
	});
}

jQuery.fn.un_z_checkbox = function() {
	return this.each(function() {
		var theRealCheckbox = jQuery(this).find('input[type=checkbox]');
		jQuery(this).replaceWith(theRealCheckbox);
		jQuery(theRealCheckbox).removeClass('z_check_hidden');
	});
}

