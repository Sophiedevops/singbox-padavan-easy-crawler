(function () {
    'use strict';

    var StreamProxy = {
        // Уникальный ключ для сохранения в памяти ТВ
        storageKey: 'streamproxy_current_ip',
        defaultIP: '192.168.1.1:1081',

        init: function () {
            // Если в памяти еще пусто, записываем дефолтный адрес
            if (!Lampa.Storage.get(this.storageKey)) {
                Lampa.Storage.set(this.storageKey, this.defaultIP);
            }

            // Добавляем кнопку в раздел Настройки -> Сервер
            Lampa.SettingsApi.addParam({
                component: 'server',
                param: {
                    name: 'streamproxy_btn_edit',
                    type: 'button'
                },
                field: {
                    name: 'Прокси для видео (StreamProxy)',
                    description: 'Текущий: ' + Lampa.Storage.get(this.storageKey)
                },
                onChange: function () {
                    // При клике вызываем родную клавиатуру Лампы
                    Lampa.Input.edit({
                        title: 'Введите IP:PORT',
                        value: Lampa.Storage.get(StreamProxy.storageKey),
                        free: true,
                        nosave: true
                    }, function (new_value) {
                        // Сохраняем то, что ввел пользователь
                        Lampa.Storage.set(StreamProxy.storageKey, new_value);
                        Lampa.Noty.show('Сохранено. Выйдите и зайдите в настройки для обновления.');
                    });
                }
            });

            // Уведомление об успешной отрисовке
            setTimeout(function () {
                if (window.Lampa && window.Lampa.Noty) {
                    Lampa.Noty.show('StreamProxy 3.0: Интерфейс добавлен в Сервер');
                }
            }, 1000);
        }
    };

    // Строгое ожидание готовности ядра
    if (window.appready) {
        StreamProxy.init();
    } else {
        if (window.Lampa && window.Lampa.Listener) {
            Lampa.Listener.follow('app', function (e) {
                if (e.type == 'ready') {
                    StreamProxy.init();
                }
            });
        }
    }
})();
