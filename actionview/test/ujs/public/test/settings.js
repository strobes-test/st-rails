import $ from 'jquery';
import Rails from '../../../../app/javascript/rails-ujs/index'

$.rails = Rails

var App = App || {}
var Turbolinks = Turbolinks || {}

window.Turbolinks = Turbolinks
window.jQuery = $

QUnit.assert.callbackInvoked = function(callbackName) {
  this.ok(true, callbackName + ' callback should have been invoked')
}

QUnit.assert.callbackNotInvoked = function(callbackName) {
  this.ok(false, callbackName + ' callback should not have been invoked')
}

QUnit.assert.getRequest = function(requestEnv) {
  this.equal(requestEnv['REQUEST_METHOD'], 'GET', 'request type should be GET')
}

QUnit.assert.postRequest = function(requestEnv) {
  this.equal(requestEnv['REQUEST_METHOD'], 'POST', 'request type should be POST')
}

QUnit.assert.requestPath = function(requestEnv, path) {
  this.equal(requestEnv['PATH_INFO'], path, 'request should be sent to right URL')
}

App.getVal = function(el) {
  return el.is('input,textarea,select') ? el.val() : el.text()
}

App.disabled = function(el) {
  return el.is('input,textarea,select,button') ?
    (el.is(':disabled') && $.rails.getData(el[0], 'ujs:disabled')) :
    $.rails.getData(el[0], 'ujs:disabled')
}

QUnit.assert.enabledState = function(el, text) {
  this.ok(!App.disabled(el), el.get(0).tagName + ' should not be disabled')
  this.equal(App.getVal(el), text, el.get(0).tagName + ' text should be original value')
}

QUnit.assert.disabledState = function(el, text) {
  this.ok(App.disabled(el), el.get(0).tagName + ' should be disabled')
  this.equal(App.getVal(el), text, el.get(0).tagName + ' text should be disabled value')
}

// hijacks normal form submit; lets it submit to an iframe to prevent
// navigating away from the test suite
$(document).bind('submit', function(e) {
  if (!e.isDefaultPrevented()) {
    var form = $(e.target), action = form.attr('action'),
        name = 'form-frame' + jQuery.guid++,
        iframe = $('<iframe name="' + name + '" />'),
        iframeInput = '<input name="iframe" value="true" type="hidden" />',
        targetInput = '<input name="_target" value="' + (form.attr('target') || '') + '" type="hidden" />'

    if (action && action.indexOf('iframe') < 0) {
      if (action.indexOf('?') < 0) {
        form.attr('action', action + '?iframe=true')
      } else {
        form.attr('action', action + '&iframe=true')
      }
    }
    form.attr('target', name).append(iframeInput, targetInput)
    $('#qunit-fixture').append(iframe)
    $.event.trigger('iframe:loading', form)
  }
})

var _MouseEvent = window.MouseEvent

try {
  new _MouseEvent()
} catch (e) {
  _MouseEvent = function(type, options) {
    var evt = document.createEvent('MouseEvents')
    evt.initMouseEvent(type, options.bubbles, options.cancelable, window, options.detail, 0, 0, 80, 20, options.ctrlKey, options.altKey, options.shiftKey, options.metaKey, options.button, null)
    return evt
  }
}

$.fn.extend({
  // trigger a native click event
  triggerNative: function(type, options) {
    var el = this[0],
        event,
        Evt = {
          'click': _MouseEvent,
          'change': Event,
          'pageshow': PageTransitionEvent,
          'submit': Event
        }[type]

    options = options || {}
    options.bubbles = true
    options.cancelable = true

    event = new Evt(type, options)

    el.dispatchEvent(event)

    if (type === 'submit' && !event.defaultPrevented) {
      el.submit()
    }
    return this
  },
  bindNative: function(event, handler) {
    if (!handler) return this

    var el = this[0]
    el.addEventListener(event, function(e) {
      var args = []
      if (e.detail) {
        args = e.detail.slice()
      }
      args.unshift(e)
      return handler.apply(el, args)
    }, false)

    return this
  }
})

Turbolinks.clearCache = function() {}
Turbolinks.visit = function() {}
