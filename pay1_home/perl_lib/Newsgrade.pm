package Newsgrade;

sub Header {
return <<END_HEADER;

<table width="760" border="0" cellpadding="0" cellspacing="0">
			<tbody><tr> 
				<td width="10"> </td>
	    		<td width="610" valign="top" align="center"> 
	    		</td>
				<td width="140"> </td>
	  		</tr>
	  		<tr>
	  			<td width="10"> </td>
	    		<td width="610" valign="top" bgcolor="#ffffff"> 
	      			<table width="610" height="600" border="1" cellspacing="0" cellpadding="0" bordercolor="#a6a6a6">
	        			<tbody><tr valign="top"> 
	          				<td>
	            				<table width="610" border="0" cellspacing="0" cellpadding="0">
	            		  			<tbody><tr>
	                					<td width="10"> </td>
										<td class="smalltext">
	                 						<!-- Start Top Well -->
	                  						<img src="/logos/newsgradeco_logo.gif"><br>
											Tag line here...
		              						<!-- End Top Well -->
	                					</td>
										<td align="right" class="link">
											<a href="#">Home</a> <br>
											<a href="#">Sign Up</a> <br>
											<a href="#">Log In</a> <br>
											<a href="#">Help</a> 
										</td>
	              					</tr>
	            				</tbody></table>
	            				<!-- Start Main Well -->
	            				<table width="610" cellpadding="0" cellspacing="0" border="0">
	              					<tbody><tr valign="top">
	              						<td><img src="logos/newsgradeco_borderdotgray2.gif" width="610" height="4"></td>
	              					</tr>
	              					<tr valign="top">
	                					<td>
END_HEADER
}

sub Footer {
return <<END_FOOTER;
</td>
	              					</tr>
	            				</tbody></table>
	            				<!-- End Main Well -->
	          				</td>
	        			</tr>
	      			</tbody></table>
				</td>
	     		<td width="140" valign="top" rowspan="2"> 
	    		</td>
	  		</tr>
	  		<tr>
	  			<td width="10"> </td> 
	    		<td width="610" valign="top"> 
					<!-- Start Footer Well -->
					<table width="610" border="0" cellspacing="0" cellpadding="2">
	<tbody><tr>
		<td align="left" class="smalltext">©2002 Securities Analysis Corporation, a Subsidiary of Newsgrade Corporation.</td>
		<td align="right"><img src="/logos/newsgradeco_icon.gif" width="28" height="22"></td>
	</tr>
	<tr>
		<td colspan="2">
			<table width="610" border="0" cellspacing="0" cellpadding="3">
				<tbody><tr>
					<td align="left"><a href="#" class="link">Data Sources</a></td>
					<td width="2"> </td>
					<td align="left"><a href="#" class="link">Terms of Service</a></td>
					<td width="2"> </td>
					<td align="right"><a href="#" class="link">Privacy</a></td>
					<td width="2"> </td>
					<td align="right"><a href="#" class="link">About Us</a></td>
				</tr>
			</tbody></table>
		</td>
	</tr>
</tbody></table>

					<!-- End Footer Well -->
				</td>
	  		</tr>
		</tbody></table>
END_FOOTER
}

1;
#end
