local network = require("network")

print("Подключение к Firebase...")

local test_data = '{"message": "Привет! Связь работает отлично!", "time": "Тест пройден"}'
local success, result = network.put("/test", test_data)

if success then
    print("УСПЕХ! Данные отправлены в базу.")
else
    print("ОШИБКА: " .. tostring(result))
end
