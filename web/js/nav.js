$(document).ready(function() {
	var links = [
		{
			label: 'Games',
			url: 'index.html'
		},
		{
			label: 'Team Season Stats',
			url: 'cumulative.html?g=teamgames.json&c=teamcumulative.json&t=t'
		},
		{
			label: 'Roster',
			url: 'roster.html'
		},
		{
			label: 'Player Compare',
			url: 'playercompare.html'
		},
		{
			label: 'Gallery',
			url: 'gallery.html'
		}
	];
	var navbarList = $('#navbarList');
	var page = window.location.pathname.split("/").pop().toLowerCase();
	
	$.each(links, function(i, l) {
		var cls = (page == l.url.toLowerCase())
			? 'class="active"'
			: '';
		navbarList.append(
			$('<li><a ' + cls + ' href="' + l.url + '">' + l.label + '</a></li>'));
	});
});