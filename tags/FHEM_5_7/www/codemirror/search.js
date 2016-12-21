(function(f){"object"==typeof exports&&"object"==typeof module?f(require("../../lib/codemirror"),require("./searchcursor"),require("../dialog/dialog")):"function"==typeof define&&define.amd?define(["../../lib/codemirror","./searchcursor","../dialog/dialog"],f):f(CodeMirror)})(function(f){function x(a,b){"string"==typeof a?a=new RegExp(a.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g,"\\$&"),b?"gi":"g"):a.global||(a=new RegExp(a.source,a.ignoreCase?"gi":"g"));return{token:function(b){a.lastIndex=b.pos;
var c=a.exec(b.string);if(c&&c.index==b.pos)return b.pos+=c[0].length,"searching";c?b.pos=c.index:b.skipToEnd()}}}function y(){this.overlay=this.posFrom=this.posTo=this.lastQuery=this.query=null}function h(a){return a.state.search||(a.state.search=new y)}function k(a){return"string"==typeof a&&a==a.toLowerCase()}function l(a,b,d){return a.getSearchCursor(b,d,k(b))}function z(a,b,d,c){a.openDialog(b,c,{value:d,selectValueOnOpen:!0,closeOnEnter:!1,onClose:function(){g(a)}})}function n(a,b,d,c,e){a.openDialog?
a.openDialog(b,e,{value:c,selectValueOnOpen:!0}):e(prompt(d,c))}function A(a,b,d,c){if(a.openConfirm)a.openConfirm(b,c);else if(confirm(d))c[0]()}function r(a){return a.replace(/\\(.)/g,function(a,d){return"n"==d?"\n":"r"==d?"\r":d})}function t(a){var b=a.match(/^\/(.*)\/([a-z]*)$/);if(b)try{a=new RegExp(b[1],-1==b[2].indexOf("i")?"":"i")}catch(d){}else a=r(a);if("string"==typeof a?""==a:a.test(""))a=/x^/;return a}function u(a,b,d){b.queryText=d;b.query=t(d);a.removeOverlay(b.overlay,k(b.query));
b.overlay=x(b.query,k(b.query));a.addOverlay(b.overlay);a.showMatchesOnScrollbar&&(b.annotate&&(b.annotate.clear(),b.annotate=null),b.annotate=a.showMatchesOnScrollbar(b.query,k(b.query)))}function m(a,b,d){var c=h(a);if(c.query)return p(a,b);var e=a.getSelection()||c.lastQuery;if(d&&a.openDialog){var q=null;z(a,'Search: <input type="text" style="width: 10em" class="CodeMirror-search-field"/> <span style="color: #888" class="CodeMirror-search-hint">(Use /re/ syntax for regexp search)</span>',e,function(b,
e){f.e_stop(e);b&&(b!=c.queryText&&u(a,c,b),q&&(q.style.opacity=1),p(a,e.shiftKey,function(b,c){var e;3>c.line&&document.querySelector&&(e=a.display.wrapper.querySelector(".CodeMirror-dialog"))&&e.getBoundingClientRect().bottom-4>a.cursorCoords(c,"window").top&&((q=e).style.opacity=.4)}))})}else n(a,'Search: <input type="text" style="width: 10em" class="CodeMirror-search-field"/> <span style="color: #888" class="CodeMirror-search-hint">(Use /re/ syntax for regexp search)</span>',"Search for:",e,function(e){e&&
!c.query&&a.operation(function(){u(a,c,e);c.posFrom=c.posTo=a.getCursor();p(a,b)})})}function p(a,b,d){a.operation(function(){var c=h(a),e=l(a,c.query,b?c.posFrom:c.posTo);if(!e.find(b)&&(e=l(a,c.query,b?f.Pos(a.lastLine()):f.Pos(a.firstLine(),0)),!e.find(b)))return;a.setSelection(e.from(),e.to());a.scrollIntoView({from:e.from(),to:e.to()},20);c.posFrom=e.from();c.posTo=e.to();d&&d(e.from(),e.to())})}function g(a){a.operation(function(){var b=h(a);if(b.lastQuery=b.query)b.query=b.queryText=null,a.removeOverlay(b.overlay),
b.annotate&&(b.annotate.clear(),b.annotate=null)})}function v(a,b,d){a.operation(function(){for(var c=l(a,b);c.findNext();)if("string"!=typeof b){var e=a.getRange(c.from(),c.to()).match(b);c.replace(d.replace(/\$(\d)/g,function(a,b){return e[b]}))}else c.replace(d)})}function w(a,b){if(!a.getOption("readOnly")){var d=a.getSelection()||h(a).lastQuery,c=b?"Replace all:":"Replace:";n(a,c+' <input type="text" style="width: 10em" class="CodeMirror-search-field"/> <span style="color: #888" class="CodeMirror-search-hint">(Use /re/ syntax for regexp search)</span>',
c,d,function(c){c&&(c=t(c),n(a,'With: <input type="text" style="width: 10em" class="CodeMirror-search-field"/>',"Replace with:","",function(d){d=r(d);if(b)v(a,c,d);else{g(a);var f=l(a,c,a.getCursor()),h=function(){var b=f.from(),g;if(!(g=f.findNext())&&(f=l(a,c),!(g=f.findNext())||b&&f.from().line==b.line&&f.from().ch==b.ch))return;a.setSelection(f.from(),f.to());a.scrollIntoView({from:f.from(),to:f.to()});A(a,"Replace? <button>Yes</button> <button>No</button> <button>All</button> <button>Stop</button>",
"Replace?",[function(){k(g)},h,function(){v(a,c,d)}])},k=function(a){f.replace("string"==typeof c?d:d.replace(/\$(\d)/g,function(b,c){return a[c]}));h()};h()}}))})}}f.commands.find=function(a){g(a);m(a)};f.commands.findPersistent=function(a){g(a);m(a,!1,!0)};f.commands.findNext=m;f.commands.findPrev=function(a){m(a,!0)};f.commands.clearSearch=g;f.commands.replace=w;f.commands.replaceAll=function(a){w(a,!0)}});