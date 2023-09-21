/* 
scrolly.js - a custom jQuery scrollbar
copyright 2015 Plug and Pay Technologies
written by Christopher Isomaki
*/
(function ($) {
	$.fn.scrolly = function(height) {
		var scrollable = this;
	
		var scrollbarTimer;
		var preventScrollbarFade = false;
		
		scrollable.css('position','absolute');
		scrollable.css('top','0px');
		scrollable.wrap('<div class="scrolly-scrollview-viewport">');
		
		viewport = scrollable.parent();
		// set height and width
		viewport.css('width',scrollable.css('width'));
		viewport.css('height',height)
		
		viewport.wrap('<div class="scrolly-scrollview-wrapper">');
		wrapper = viewport.parent();
		wrapper.css('width',scrollable.css('width'));
		
		var scrollbar = jQuery('<div class="scrolly-scrollview-scrollbar">');
		scrollbar.css('height',height);
		wrapper.append(scrollbar);
			
		var scrollbarHandle = jQuery('<div class="scrolly-scrollview-handle">');
		scrollbarHandle.css('height',scrollbar.height()/2);
		scrollbarHandle.on('mousedown',function() { preventScrollbarFade = true; })
		scrollbarHandle.on('mouseup',function() { preventScrollbarFade = false; })
	
		// scrollbar can scroll list.
		scrollbar.append(scrollbarHandle).promise().done(function() {
			scrollbarHandle.draggable({
				axis: 'y',
				containment: 'parent',
				drag: function() {
					var yPosition  = parseInt(scrollbarHandle.css('top'));
					var scrollPercent = yPosition/(scrollbar.height())
					var scrollContentTo = scrollPercent * (scrollable.height() - viewport.height()) * 2;
					scrollable.css('top','-' + scrollContentTo + 'px');
				}
			});
		});
		
		// mouse/trackpad can scroll list
		wrapper.bind('mousewheel',function(event,delta) {
			event.preventDefault();
			
			var scrollablePosition = parseInt(scrollable.css('top').replace('px',''))
			var scrollableMinTop = viewport.height() - scrollable.height();
			var scrollableMaxTop = 0;
			if (scrollablePosition > scrollableMaxTop) {
				scrollablePosition = scrollableMaxTop;
			} else if (scrollablePosition < scrollableMinTop) {
				scrollablePosition = scrollableMinTop;
			}
			
			scrollable.css('top',scrollablePosition + (10 * delta));
			
			if (scrollablePosition == 0) {
				scrollbarHandle.css('top','0px');
			} else {
				var percent = (scrollablePosition / scrollableMinTop);
				scrollbarHandle.css('top',percent * 0.5 * scrollbar.height());
			}
		});
		
		scrollbar.bind('click',function(event) {
			var clickPosition = event.offsetY;
			clickPercent = clickPosition/scrollbar.height()
			var scrollContentTo = clickPercent * (scrollable.height() - viewport.height());
			scrollable.css('top','-' + scrollContentTo + 'px');
			scrollbarHandle.css('top',clickPercent * 0.5 * scrollbar.height());
			preventScrollbarFade = false;
		});
	
		wrapper.on('mouseover', function() {
			clearTimeout(scrollbarTimer);
			scrollbar.animate({'opacity': 1},500);
		});
		
		wrapper.on('mouseout', function() {
			if (!preventScrollbarFade) {
				scrollbarTimer = setTimeout(function() {
					scrollbar.animate({'opacity': 0},1000);
				},500);
			}
		});
	
		return scrollable;
	}
}(jQuery))
