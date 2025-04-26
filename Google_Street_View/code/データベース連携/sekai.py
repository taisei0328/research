import requests
from bs4 import BeautifulSoup
import random
import re

# Google APIキーの設定
streetview_api_key = 'AIzaSyB-IZE4qhNO3ce-enFIky64yTNkS-8iJB0'

# 度分秒（DMS）を十進度（Decimal Degrees）に変換
def dms_to_dd(degrees, minutes, seconds, direction):
    """
    度分秒 (DMS) を十進度 (Decimal Degrees) に変換します。
    
    :param degrees: 度部分（整数）
    :param minutes: 分部分（整数）
    :param seconds: 秒部分（整数）
    :param direction: N/S または E/W（方角）
    
    :return: 十進度（Decimal Degrees）
    """
    dd = degrees + (minutes / 60.0) + (seconds / 3600.0)
    
    # 南または西の場合はマイナスを付ける
    if direction in ['S', 'W']:
        dd = -dd
    
    return dd

# 度分秒（DMS）形式の文字列を解析し、Decimal Degreesに変換
def parse_dms(dms_string):
    """
    度分秒形式（° 　′ ″）の文字列を解析し、十進度に変換します。
    
    :param dms_string: 度分秒形式の緯度経度文字列
    :return: 十進度（Decimal Degrees）
    """
    pattern = r'(\d{1,3})\s*°\s*(\d{1,2})\s*′\s*(\d{1,2})\s*″\s*([NSEW])'
    match = re.match(pattern, dms_string.strip())
    if match:
        degrees = int(match.group(1))
        minutes = int(match.group(2))
        seconds = int(match.group(3))
        direction = match.group(4)
        return dms_to_dd(degrees, minutes, seconds, direction)
    return None

# GeoNamesから緯度経度を取得
def get_lat_lon(city_name):
    search_url = f"http://www.geonames.org/search.html?q={city_name}&country="
    response = requests.get(search_url)

    if response.status_code != 200:
        print("Failed to retrieve the search page.")
        return None

    soup = BeautifulSoup(response.text, 'html.parser')
    rows = soup.find_all('tr', class_='odd') + soup.find_all('tr', class_='even')
    
    lat_lon_list = []
    
    for row in rows:
        columns = row.find_all('td')
        if len(columns) > 4:
            place = columns[1].text.strip()
            lat = columns[4].text.strip()  # 緯度（度分秒形式）
            lon = columns[5].text.strip()  # 経度（度分秒形式）
            
            # 緯度経度を度分秒形式から十進度に変換
            lat_dd = parse_dms(lat)
            lon_dd = parse_dms(lon)
            
            if lat_dd is not None and lon_dd is not None:
                lat_lon_list.append((place, lat_dd, lon_dd))
            else:
                print(f"Skipping invalid entry: {place}, {lat}, {lon}")
    
    if len(lat_lon_list) == 0:
        print("Latitude and Longitude not found.")
        return None
    
    return lat_lon_list

# ランダムに指定された数の場所を選ぶ
def get_random_lat_lon(city_name, num_places):
    lat_lon_list = get_lat_lon(city_name)
    
    if lat_lon_list:
        # 入力された地点数に基づいてランダムに選ぶ
        random_places = random.sample(lat_lon_list, num_places)
        
        for place, lat, lon in random_places:
            print(f"Place: {place}, Latitude: {lat}, Longitude: {lon}")
            # Street View画像を取得
            for heading in [0, 90, 180, 270]:  # 4つの方向（0, 90, 180, 270度）でStreet View画像を取得
                fetch_streetview_image(lat, lon, heading, place)
    else:
        print("No places found for the given city.")

# Street View画像を取得する関数
def fetch_streetview_image(lat, lon, heading, place):
    streetview_url = f'https://maps.googleapis.com/maps/api/streetview?size=600x400&location={lat},{lon}&fov=120&heading={heading}&key={streetview_api_key}'
    response = requests.get(streetview_url)
    if response.status_code == 200:
        filename = f'streetview_image_{place}_{heading}.jpg'
        with open(filename, 'wb') as f:
            f.write(response.content)
        print(f"Image saved: {filename}")
    else:
        print(f"Failed to retrieve street view image for {place} at heading {heading}. Status: {response.status_code}")

# 実行例
def main():
    # ユーザーから入力を受け付ける
    city_name = input("検索したい都市名を入力してください: ")
    num_places = int(input("取得する地点数を入力してください: "))
    
    get_random_lat_lon(city_name, num_places)

if __name__ == "__main__":
    main()

