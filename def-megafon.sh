#!/bin/bash

#файл DEF-кодов
DOWNFILE='https://rossvyaz.ru/data/DEF-9xx.html';
#рабочая папка
TMPDIR='./';
#файл, где сохраним csv формат кодов
FILENAME='codes';
#какой регион будем выделять
REGION='Новосибирская область';
OPERATOR='МегаФон';
#id outbound route в FreePBX mysql БД
ROUTE_ID=5

FREEPBX_LOGIN='admin'
FREEPBX_PASS='mahapharata'
FREEPBX_ADRESS='192.168.88.9'

#качаем и преобразуем в формат csv
wget -c -q -O - $DOWNFILE | grep "^<tr>" | sed -e 's/<\/td>//g' -e 's/<tr>//g' -e 's/<\/tr>//g' -e 's/[\t]//g' -e 's/^<td>//g' -e 's/<td>/;/g' | iconv -c -f WINDOWS-1251 -t UTF8 | grep "$OPERATOR" > $TMPDIR/$FILENAME

#проверяем не скачали ли пустышку
check=`cat $TMPDIR/$FILENAME`
if [ "$check" == "" ]; then
exit 0
fi

#скрипт на awk генерации Dial Patterns
awk_code='
#функция определения диапазона
function ret_diap(from,to)
{
     if ((to-from)==0) return from;
     else if ((to-from)==9) return "X";
     else return "["from"-"to"]";
}
#основная функция
{
        DEF=$1;
        razm=1;
        delete out_str;
        for (i=1; i <= length($3);i++)
        {
                if ((substr($3,i,1)-substr($2,i,1))==0)
                        {
                                for (r=1; r <= razm;r++)
                                {
                                        out_str[r]=out_str[r] substr($3,i,1);
                                }

                        }
                else
                        {
                                if ((substr($3,i,1)-substr($2,i,1))==9)
                                {
                                        for (r=1; r <= razm;r++)
                                        {
                                                out_str[r]=out_str[r]"X";
                                        }

                                }
                                else
                                {
                                        if (substr($3,i,1)-substr($2,i,1)>=1 && substr($3,(i+1),1)-substr($2,(i+1),1)!=9)
                                        {
                                                count=1;
                                                init_str=out_str[1];
                                                for (j=substr($2,(i),1); j < substr($3,(i),1);j++)
                                                {
                                                        if (count==1)
                                                        {
                                                                out_str[count]=init_str j ret_diap(substr($2,(i+1),1),9);
                                                        }
                                                        else
                                                        {
                                                                out_str[count]=init_str ret_diap(j,(substr($3,(i),1)-1)) "X";
                                                                j=(substr($3,(i),1)-1);
                                                        }
                                                        count++;
                                                        if (razm<count) razm=count;
                                                }
                                                out_str[count]=init_str j ret_diap(0,substr($3,(i+1),1));
                                                i++;
                                        }
                                        else
                                        {
                                                for (r=1; r <= razm;r++)
                                                {
                                                        out_str[r]=out_str[r]"["substr($2,i,1)"-"substr($3,i,1)"]";
                                                }
                                        }
                                }
                        }
        }
        for (r in out_str)
        {
                print 8DEF out_str[r];
        }
}'

#исполняем код awk, на выходе - Dial Patterns
cat codes | awk -F ';' "$awk_code" > patterns

#удаляем старые паттерны
sql="DELETE FROM outbound_route_patterns WHERE route_id=$ROUTE_ID"
echo $sql
mysql -Dasterisk -e "$sql"

#формируем новые паттерны
sql="INSERT INTO outbound_route_patterns (route_id,match_pattern_pass,match_pattern_prefix) VALUES "
n=1
for i in `cat patterns`
do
        if [ $n -eq 1 ]; then  sql="$sql ($ROUTE_ID,'$i','')"
        else sql="$sql, ($ROUTE_ID,'$i','')"
        fi
        let n=n+1
done
echo $sql
mysql -Dasterisk -e "$sql"

#авторизуемся на freepbx
curl -c cookies -d 'username=$FREEPBX_LOGIN&password=$FREEPBX_PASS&submit=Login' http://$FREEPBX_ADRESS/admin/config.php > /dev/null
#перезагружаем конфигурацию
curl -b cookies http://$FREEPBX_ADRESS/admin/config.php?handler=reload > /dev/null
