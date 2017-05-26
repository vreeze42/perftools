var COLLAPSABLE_PARENT_NAME = "collapsable";
var COLLAPSABLE_PARENT_TYPE = "div";
var COLLAPSABLE_CHILD_TYPE = "p";

var COLLAPSABLE_EXPAND = "[+]";
var COLLAPSABLE_SHRINK = "[-]";

init = function() {
    if(document.getElementById && document.createTextNode) {
        var entries = document.getElementsByTagName(COLLAPSABLE_PARENT_TYPE);
        for(i=0;i<entries.length;i++)
            if (entries[i].className==COLLAPSABLE_PARENT_NAME)
                assignCollapse(entries[i]);
    }
}

assignCollapse = function (div) {
    var button = document.createElement('a');
    button.style.cursor='pointer';
    button.setAttribute('expand', COLLAPSABLE_EXPAND);
    button.setAttribute('shrink', COLLAPSABLE_SHRINK);
    button.setAttribute('state', -1);
    button.innerHTML='dsds';
    div.insertBefore(button, div.getElementsByTagName(COLLAPSABLE_CHILD_TYPE)[0]);

    button.onclick=function(){
        var state = -(1*this.getAttribute('state'));
        this.setAttribute('state', state);
        this.parentNode.getElementsByTagName(COLLAPSABLE_CHILD_TYPE)[0].style.display=state==1?'none':'block';
        this.innerHTML = this.getAttribute(state==1?'expand':'shrink');
    };                   
    button.onclick();
}


window.onload=init;

