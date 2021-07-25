$.urlParam = function(name){
	var results = new RegExp('[\?&]' + name + '=([^&#]*)').exec(window.location.href);
	if(results) {
		return results[1] || 0;
	}
	return null;
};

$.getObjValue = function(obj, propName) {
	var props = propName.split('.');
	$.each(props, function(idx, p) {
		if(null == obj) {
			return;
		}
		obj = obj[p];
	});
	
	if(null == obj) {
		console.log(propName + ' value is null!');
	}
	var x = (obj && obj.indexOf) ? obj.indexOf('%') : -1;
	if(x >= 0) {
		obj = obj.substr(0, x);
	}
	return obj;
};

$.buildParamUrl = function(url, paramObj) {
	var full = url + '?';
	for(var k in paramObj) {
		full += k + '=' + encodeURIComponent(paramObj[k]) + '&';
	}
	
	return full;
};
