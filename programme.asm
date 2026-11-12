; получение hex представления exe-файла и запись его в текстовый файл
; $bytes = [System.IO.File]::ReadAllBytes(".\trial period.exe"); $hex = [System.BitConverter]::ToString($bytes).Replace("-", ""); [System.IO.File]::WriteAllText(".\trial period.hex.txt", $hex)
; вписать нужные байты в файл можно добавив 


bits 64
default rel

extern CreateFileA
extern GetFileSizeEx
extern ReadFile
extern CloseHandle
extern ExitProcess
extern GetStdHandle
extern WriteConsoleW
extern WriteConsoleA
extern GetLocalTime
extern WriteFile
extern SetFilePointerEx
extern CreateThread
extern Sleep
extern GetLastError
extern ReadConsoleW
extern SetFilePointerEx
extern ReadFile


%define STD_OUTPUT_HANDLE -11
%define STD_INPUT_HANDLE -10
%define GENERIC_READ 0x80000000
%define FILE_SHARE_READ 1
%define OPEN_ALWAYS 4
%define FILE_ATTRIBUTE_NORMAL 0x80
%define BUFFER_SIZE 65536
%define GENERIC_WRITE 0x40000000
%define FILE_ATTRIBUTE_HIDDEN 0x2
%define FILE_APPEND_DATA 0x00000004
%define FILE_BEGIN 0


%macro PUT2 1
    movzx eax, word [system_time + %1]
    xor edx, edx
    mov ecx, 10
    div ecx
    add al, '0'
    mov [rdi], al
    add dl, '0'
    mov [rdi + 1], dl
    add rdi, 2
%endmacro

%macro PUT3 1
    movzx eax, word [system_time + %1]
    xor edx, edx
    mov ecx, 100
    div ecx
    add al, '0'
    mov [rdi], al

    mov eax, edx
    xor edx, edx
    mov ecx, 10
    div ecx
    add al, '0'
    mov [rdi + 1], al
    add dl, '0'
    mov [rdi + 2], dl
    add rdi, 3
%endmacro

%macro PUT4YEAR 0
    movzx eax, word [system_time]
    xor edx, edx
    mov ecx, 1000
    div ecx
    add al, '0'
    mov [rdi], al

    mov eax, edx
    xor edx, edx
    mov ecx, 100
    div ecx
    add al, '0'
    mov [rdi + 1], al

    mov eax, edx
    xor edx, edx
    mov ecx, 10
    div ecx
    add al, '0'
    mov [rdi + 2], al
    add dl, '0'
    mov [rdi + 3], dl
    add rdi, 4
%endmacro

section .data
    file_name db "C:\Users\User\Downloads\N0va Desсktop_2023-01-06.log", 0

    needle    db "A455448427BA5D64CC71F528A2226DC4E41C36EA5464154EF1244C416984C4BF"
    needle_chars equ ($ - needle)

    log_suffix db "] [info] [thread: 11988] MSG_UPDATE_DXWIN PlayWindow Hwnd is: "
               db "A455448427BA5D64CC71F528A2226DC4E41C36EA5464154EF1244C416984C4BF"
               db 13, 10
    log_suffix_len equ $ - log_suffix

    msg db "The programme has been launched on this device more than three times. You have reached the end of your trial period; please purchase the paid version.", 0
    msg_len equ ($ - msg)  
    
    msg_time db "The programme ran for longer than the specified trial period. It was forcibly terminated. This attempt to use the programme was blocked.", 0
    msg_time_len equ ($ - msg_time - 1)

    file_offset dq 0

    prompt:
        dw 0x0412, 0x0432, 0x0435, 0x0434, 0x0438, 0x0442, 0x0435         ; "Введите"
        dw 0x0020                                                         ; " "
        dw 0x0441, 0x0442, 0x0440, 0x043E, 0x043A, 0x0443                 ; "строку"
        dw 0x0020, 0x003A, 0x0020                                         ; " : "
    prompt_chars equ ($ - prompt) / 2

    file_name_prg db "output.txt", 0
    utf16_bom  db 0xFF, 0xFE

    already_message:
        dw 0x0421, 0x0442, 0x0440, 0x043E, 0x043A, 0x0430 ; Строка
        dw 0x0020, 0x0443, 0x0436, 0x0435                 ; " уже"
        dw 0x0020, 0x0435, 0x0441, 0x0442, 0x044C         ; " есть"
        dw 0x0020, 0x0432, 0x0020                         ; " в "
        dw 0x0444, 0x0430, 0x0439, 0x043B, 0x0435         ; "файле"
        dw 0x002E, 0x000D, 0x000A                         ; ".\r\n"
    already_message_chars equ ($ - already_message) / 2

section .bss
    alignb 8
    file_handle         resq 1
    file_size           resq 1
    bytes_read          resd 1
    error_code          resd 1
    bytes_written       resd 1
    occurrence_count    resd 1
    buffer              resb BUFFER_SIZE
    system_time         resw 8
    log_buffer          resb 256
    console_written     resd 1


    alignb 8
    stdin_handle  resq 1
    stdout_handle resq 1

    chars_read    resd 1

    alignb 2
    input_buffer  resw 256

    file_bytes_read resd 1
    search_chars    resd 1

    alignb 2
    search_buffer   resb 1048576

    failure_stage resd 1

section .text
    global main

main:
    sub rsp, 56

    ; ------ Запуск потока для ожидания полторы минуты < начало кода > -----

    ; Запустить таймерный поток
    xor ecx, ecx
    xor edx, edx
    lea r8, [timeout_thread]
    xor r9d, r9d
    mov qword [rsp + 32], 0
    mov qword [rsp + 40], 0
    call CreateThread

    test rax, rax
    jnz .timer_created

    ; CreateThread не создал поток
    mov ecx, 5
    call ExitProcess

.timer_created:
    ; Закрытие дескриптора не останавливает сам поток
    mov rcx, rax
    call CloseHandle

    ; ------ Запуск потока для ожидания полторы минуты < конец кода > -----


    ; ------ Создать файл (скрытый), если он не существует, и открыть его для чтения и записи  < начало кода > ----- 

    lea rcx, [file_name]
    mov edx, GENERIC_READ | FILE_APPEND_DATA
    mov r8d, FILE_SHARE_READ
    xor r9d, r9d
    mov dword [rsp + 32], OPEN_ALWAYS
    mov dword [rsp + 40], FILE_ATTRIBUTE_HIDDEN
    mov qword [rsp + 48], 0
    call CreateFileA

    ; ------ Создать файл (скрытый), если он не существует, и открыть его для чтения и записи  < конец кода > -----

    cmp rax, -1                                                                               ; ошибка при открытии файла
    mov [error_code], 1                                                                       ; обозначение ошибки в первом вызове функции CreateFileA
    je .error                                                                                 ; прыжок к метке с кодом завершения 255
    mov [file_handle], rax

    ; ------ Получить местные дату и время < начало кода > ------

    lea rcx, [system_time]
    call GetLocalTime
    
    ; ------ Получить местные дату и время < конец кода > ------

    ; ------ Сформировать строку для записи в файл < начало кода > ------

    ; Сформировать [гггг-мм-дд чч:мм:сс.мсс]
    lea rdi, [log_buffer]
    mov byte [rdi], '['
    inc rdi

    PUT4YEAR
    mov byte [rdi], '-'
    inc rdi
    PUT2 2                                                                                    ; месяц
    mov byte [rdi], '-'
    inc rdi
    PUT2 6                                                                                    ; день
    mov byte [rdi], ' '
    inc rdi
    PUT2 8                                                                                    ; часы
    mov byte [rdi], ':'
    inc rdi
    PUT2 10                                                                                   ; минуты
    mov byte [rdi], ':'
    inc rdi
    PUT2 12                                                                                   ; секунды
    mov byte [rdi], '.'
    inc rdi
    PUT3 14                                                                                   ; миллисекунды

    ; Добавить оставшуюся часть строки и перевод строки.
    lea rsi, [log_suffix]
    mov ecx, log_suffix_len
    rep movsb

    ; ------ Сформировать строку для записи в файл < конец кода > ------

    ; ------ Записать сформированную строку в конец файла < начало кода > ------

    mov rcx, [file_handle]
    lea rdx, [log_buffer]
    mov r8, rdi
    sub r8, rdx
    lea r9, [bytes_written]
    mov qword [rsp + 32], 0
    call WriteFile

    test eax, eax
    mov [error_code], 2                                                                       ; Обозначение ошибки при вызове функции WriteFile для записи скрытого лога 
    jz .write_error

    ; ------ Записать сформированную строку в конец файла < конец кода > ------

    ; ------ Получить размер файла < начало кода >------

    mov rcx, [file_handle]
    lea rdx, [file_size]
    call GetFileSizeEx

    ; ------ Получить размер файла < конец кода >------

    test eax, eax
    jz .close_error

    ; Буфер вмещает не более BUFFER_SIZE байт.
    cmp qword [file_size], BUFFER_SIZE
    ja .close_error

    mov rcx, [file_handle]
    xor edx, edx                                                                              ; смещение 0
    xor r8d, r8d                                                                              ; lpNewFilePointer = NULL
    mov r9d, FILE_BEGIN
    call SetFilePointerEx
    test eax, eax
    jz .close_error

    ; Прочитать файл.
    mov rcx, [file_handle]
    lea rdx, [buffer]
    mov r8d, [file_size]
    lea r9, [bytes_read]
    mov qword [rsp + 32], 0
    call ReadFile
    test eax, eax
    jz .close_error

    ; Если файл короче искомой строки, совпадений нет.
    mov eax, [bytes_read]
    cmp eax, needle_chars
    jb .finish_count

    ; r8d — последний допустимый индекс начала совпадения.
    mov r8d, eax
    sub r8d, needle_chars
    xor r10d, r10d                                                                            ; индекс начала поиска

.search_start:
    cmp r10d, r8d
    ja .finish_count

    xor r11d, r11d                                                                            ; индекс символа в needle

.compare_chars:
    cmp r11d, needle_chars
    jae .match

    mov eax, r10d
    add eax, r11d
    mov dl, [buffer + rax]
    cmp dl, [needle + r11]
    jne .next_start

    inc r11d
    jmp .compare_chars

.match:
    inc dword [occurrence_count]
    cmp dword [occurrence_count], 3
    ja .finish_count                                                                          ; найдено больше трёх — закрыть файл и завершить

.next_start:
    inc r10d                                                                                  ; шаг на 1 байт позволяет считать перекрытия
    jmp .search_start

.finish_count:
    mov rcx, [file_handle]
    call CloseHandle

    mov ecx, [occurrence_count]                                                               ; код завершения: количество, максимум 4
    cmp ecx, 3
    ja .more_than_three
    jmp main_programm

.close_error:
    mov rcx, [file_handle]
    call CloseHandle

.error:
    mov ecx, [error_code]                                                                     ; код ошибки, по номеру можно посмотреть место возникновения ошибки
    call ExitProcess

.more_than_three:
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov rcx, rax
    lea rdx, [msg]
    mov r8d, msg_len
    dec r8d                                                                                   ; не выводить завершающий ноль
    lea r9, [console_written]
    mov qword [rsp + 32], 0
    call WriteConsoleA
    
    mov ecx, 4                                                                                ; код завершения: больше трёх
    call ExitProcess


.write_error:
    mov rcx, [file_handle]
    call CloseHandle

timeout_thread:
    timeout_thread:
    sub rsp, 40
    mov ecx, 90000
    call Sleep

    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov rcx, rax
    lea rdx, [msg_time]
    mov r8d, msg_time_len
    lea r9, [console_written]
    mov qword [rsp + 32], 0
    call WriteConsoleA

    xor ecx, ecx
    call ExitProcess



; ----------------------------------------------------------------------------------------------------------------


main_programm:

    ; порядок передачи аргументов в Windows x64 ABI:
    ; rcx - 1-й аргумент
    ; rdx - 2-й аргумент
    ; r8  - 3-й аргумент
    ; r9  - 4-й аргумент
    ; дальше через стек (push)

    sub rsp, 64

    ; ------ получаем дескриптор стандартного потока вывода < начало кода > ------

    ; функция получения дескриптора стандартного потока вывода в Windows x64 ABI
    ; аргументы на ввод перед вызовом функции: - 
    ; результат возвращается в stdout_handle
    GetStdOUTHandle:
        
        ; Получить stdout.
        mov ecx, STD_OUTPUT_HANDLE                    
        call GetStdHandle
        test rax, rax
        jz .fail
        cmp rax, -1
        je .fail
        mov [stdout_handle], rax
        jmp WriteTextInConsole

        .fail:
            mov ecx, 1                      ; код завершения 1
            call ExitProcess
            

    ; ------ получаем дескриптор стандартного потока вывода < конец кода > ------




    ; ------ печатаем строку в терминал < начало кода > ------

    WriteTextInConsole:
        mov rcx, [stdout_handle]
        lea rdx, [prompt]
        mov r8d, prompt_chars
        lea r9, [bytes_written]
        mov qword [rsp + 32], 0
        call WriteConsoleW
        test eax, eax
        jz .fail
        jmp GetStdINHandle

        .fail:
            mov ecx, 2                      ; код завершения 2
            call ExitProcess

    ; ------ печатаем строку в терминал < конец кода > ------




    ; ------ получаем дескриптор стандартного потока ввода < начало кода > ------
    
    ; функция получения дескриптора стандартного потока ввода в Windows x64 ABI
    ; аргументы на ввод перед вызовом функции: -
    ; результат возвращается в stdin_handle
    GetStdINHandle:
        mov ecx, STD_INPUT_HANDLE                    
        call GetStdHandle
        test rax, rax
        jz .fail
        cmp rax, -1
        je .fail
        mov [stdin_handle], rax
        jmp ReadTextFromConsole

        .fail:
            mov ecx, 3                      ; код завершения 3
            call ExitProcess

    ; ------ получаем дескриптор стандартного потока ввода < конец кода > ------




    ; ------ читаем строку из терминала < начало кода > ------

    ; функция чтения строки из терминала в Windows x64 ABI
    ; аргументы на ввод перед вызовом функции: -
    ; результат возвращается в input_buffer и chars_read
    ; input_buffer - буфер для хранения введённой строки, chars_read - количество считанных символов
    ReadTextFromConsole:
        mov rcx, [stdin_handle]
        lea rdx, [input_buffer]
        mov r8d, 255
        lea r9, [chars_read]
        mov qword [rsp + 32], 0
        call ReadConsoleW
        test eax, eax
        jz .fail
        jmp trim_done

        .fail:
            mov ecx, 4                      ; код завершения 4
            call ExitProcess

    ; ------ читаем строку из терминала < конец кода > ------



    ; ------ обрезаем символы перевода строки из конца введённой строки < начало кода > ------

    trim_done:
    mov eax, [chars_read]
    cmp eax, 2
    jb InputTrimmed

    cmp word [input_buffer + rax * 2 - 4], 13
    jne InputTrimmed
    cmp word [input_buffer + rax * 2 - 2], 10
    jne InputTrimmed

    sub eax, 2

    InputTrimmed:
        mov [search_chars], eax

    ; ------ обрезаем символы перевода строки из конца введённой строки < конец кода > ------



    ; ------ открываем или создаём файл < начало кода > ------
    
    ; Функция открытия или создания файла в режиме OPEN_ALWAYS с правом добавления данных в конец в Windows x64 ABI
    ; аргументы на ввод перед вызовом функции: file_name_prg
    ; file_name_prg - имя файла, который нужно открыть или создать, пеердается в rcx
    ; результат возвращается в file_handle
        lea rcx, [file_name_prg]
    OpenAnExistingFile:
        mov edx, 0x80000004              ; GENERIC_READ | FILE_APPEND_DATA
        xor r8d, r8d                     ; dwShareMode = 0
        xor r9d, r9d                     ; lpSecurityAttributes = NULL
        mov dword [rsp + 32], 4          ; OPEN_ALWAYS
        mov dword [rsp + 40], 0x80       ; FILE_ATTRIBUTE_NORMAL
        mov qword [rsp + 48], 0          ; hTemplateFile = NULL
        call CreateFileA

        cmp rax, -1                      ; INVALID_HANDLE_VALUE
        je .fail
        mov [file_handle], rax
        jmp CheckingAnErrorCodeToSeeIfAFileExists

        .fail:
            mov ecx, 5                      ; код завершения 5
            call ExitProcess
    
    ; ------ открываем или создаём файл < конец кода > ------



    ; ------ открываем файл и проверяем, есть ли введённая строка в файле < начало кода > ------

    CheckingAnErrorCodeToSeeIfAFileExists:
        ; ERROR_ALREADY_EXISTS = 183: файл уже существовал.
        call GetLastError
        cmp eax, 183
        je CheckStringInFile

        ; Новый файл: сначала записываем BOM UTF-16LE.
        mov rcx, [file_handle]
        lea rdx, [utf16_bom]
        mov r8d, 2
        lea r9, [bytes_written]
        mov qword [rsp + 32], 0
        call WriteFile
        test eax, eax
        jz FileCheckFailed

    CheckStringInFile:
        mov dword [failure_stage], 71
        ; Получить размер файла.
        mov rcx, [file_handle]
        lea rdx, [file_size]
        call GetFileSizeEx
        test eax, eax
        jz FileCheckFailed

        cmp qword [file_size], 1048576
        jbe FileSizeAccepted
        cmp qword [file_size], 1048576
        ja FileCheckFailed

    FileSizeAccepted:
        ; SetFilePointerEx принимает смещение по значению, не адрес.
        mov dword [failure_stage], 73
        mov rcx, [file_handle]
        xor edx, edx                 ; liDistanceToMove = 0
        xor r8d, r8d                 ; lpNewFilePointer = NULL
        xor r9d, r9d                 ; FILE_BEGIN
        call SetFilePointerEx
        test eax, eax
        jz FileCheckFailed

        mov dword [failure_stage], 74
        mov rcx, [file_handle]
        lea rdx, [search_buffer]
        mov r8d, [file_size]
        lea r9, [file_bytes_read]
        mov qword [rsp + 32], 0
        call ReadFile
        test eax, eax
        jz FileCheckFailed

        mov dword [failure_stage], 75
        mov eax, [file_size]
        cmp [file_bytes_read], eax
        jne FileCheckFailed

        ; Убедиться, что прочитан весь файл.
        mov eax, [file_size]
        cmp [file_bytes_read], eax
        jne FileCheckFailed

        ; Пустую строку не считаем найденной.
        mov r8d, [search_chars]
        test r8d, r8d
        jz StringNotFound

        ; Перевести длину файла из байтов в 16-битные символы.
        mov r9d, [file_bytes_read]
        shr r9d, 1

        ; Если строка длиннее файла, совпадения нет.
        cmp r9d, r8d
        jb StringNotFound

        ; r9d = последний допустимый индекс начала совпадения.
        sub r9d, r8d
        xor r10d, r10d              ; индекс начала поиска

    SearchStart:
        cmp r10d, r9d
        ja StringNotFound

        xor r11d, r11d              ; индекс символа во введённой строке

    SearchCharacters:
        cmp r11d, r8d
        jae StringFound

        ; Сравнить очередной UTF-16-символ файла и введённой строки.
        mov eax, r10d
        add eax, r11d
        movzx eax, word [search_buffer + rax * 2]
        cmp ax, word [input_buffer + r11 * 2]
        jne SearchNextStart

        inc r11d
        jmp SearchCharacters

    SearchNextStart:
        inc r10d
        jmp SearchStart

    StringFound:
        ; Сообщить, что строка уже есть в файле.
        mov rcx, [stdout_handle]
        lea rdx, [already_message]
        mov r8d, already_message_chars
        lea r9, [bytes_written]
        mov qword [rsp + 32], 0
        call WriteConsoleW

        mov rcx, [file_handle]
        call CloseHandle

        xor ecx, ecx
        call ExitProcess

    StringNotFound:
        ; Совпадения нет — перейти к существующему коду добавления строки.
        jmp AppendText

    FileCheckFailed:
        mov rcx, [file_handle]
        call CloseHandle
        mov ecx, [failure_stage]
        call ExitProcess
        

    ; ------ открываем файл и проверяем, есть ли введённая строка в файле < конец кода > ------


    ; ------ добавляем BOM в файл < начало кода > ------
    AddBOMToFile:
        ; Файл только что создан — записать BOM UTF-16LE.
        mov rcx, [file_handle]
        lea rdx, [utf16_bom]
        mov r8d, 2
        lea r9, [bytes_written]
        mov qword [rsp + 32], 0
        call WriteFile
        test eax, eax
        jz .close_fail
        jmp AppendText

        .close_fail:
            mov rcx, [file_handle]
            call CloseHandle
            jmp .fail

        .fail:
            mov ecx, 6                      ; код завершения 6
            call ExitProcess

    ; ------ добавляем BOM в файл < конец кода > ------
    
    
    
    ; ------ дописываем введённую строку в конец файла < начало кода > ------   

    AppendText:
        ; Дописать введённую строку в конец файла.
        mov eax, [chars_read]
        shl eax, 1                       ; UTF-16: 2 байта на единицу
        mov r8d, eax

        mov rcx, [file_handle]
        lea rdx, [input_buffer]
        lea r9, [bytes_written]
        mov qword [rsp + 32], 0
        call WriteFile
        test eax, eax
        jz .close_fail

        mov rcx, [file_handle]
        call CloseHandle

        xor ecx, ecx                     ; код завершения 0
        call ExitProcess

    .close_fail:
        mov rcx, [file_handle]
        call CloseHandle
        jmp .fail

    .fail:
        mov ecx, 1                      ; код завершения 1
        call ExitProcess

   ; ------ дописываем введённую строку в конец файла < конец кода > ------