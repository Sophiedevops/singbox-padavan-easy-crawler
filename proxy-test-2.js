(function () {
    'use strict';

    var StreamProxy = {
        init: function () {
            // Ждем 1 секунду после запуска, чтобы точно никого не заблокировать
            setTimeout(function () {
                if (window.Lampa && window.Lampa.Noty) {
                    Lampa.Noty.show('StreamProxy 2.0: Загрузка успешна!');
                }
            }, 1000);
        }
    };

    // Запускаем только когда Лампа скажет, что она полностью готова
    if (window.appready) {
        StreamProxy.init();
    } else {
        // Если объект Lampa существует, вешаем слушателя
        if (window.Lampa && window.Lampa.Listener) {
            Lampa.Listener.follow('app', function (e) {
                if (e.type == 'ready') {
                    StreamProxy.init();
                }
            });
        }
    }
})();
