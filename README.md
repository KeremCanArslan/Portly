Backend

cd backend
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt

.env dosyasını oluşturun ve API anahtarlarınızı ekleyin:

DATABASE_URL=sqlite:///./portly.db
SECRET_KEY=your_secret_key
GROQ_API_KEY=your_groq_key


uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

Frontend

lib/services/api_service.dart dosyasını açın ve baseUrl kısmını kendi yerel IP adresinizle güncelleyin:

if (Platform.isIOS) return "http://192.168.x.x:8000/api/v1"; (ios)

flutter pub get
flutter run

Uygulama beyaz ekranda kalırsa flutter run --release komutu ile AOT modunda çalıştırılması önerilir. (ios)