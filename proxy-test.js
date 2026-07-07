(function () {
    'use strict';

    if (window.streamproxy_test_loaded) return;
    window.streamproxy_test_loaded = true;

    function runTest() {
        // Выводим только уведомление, никаких меню!
        if (window.Lampa && window.Lampa.Noty) {
            Lampa.Noty.show('StreamProxy: Загрузка прошла успешно! Ошибок нет.');
            console.log('StreamProxy: OK');
        }
    }

    // Запускаем мягкий таймер (проверка раз в полсекунды)
    var checkTimer = setInterval(function () {
        if (window.appready && window.Lampa && window.Lampa.Noty) {
            clearInterval(checkTimer);
            // Ждем еще 1 секунду после загрузки Лампы, чтобы дать ядру "перевести дух"
            setTimeout(runTest, 1000); 
        }
    }, 500);

})();
