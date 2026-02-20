# 💊 My Meds Tracker

A smart, cross-platform medication inventory and refill tracking application built with **Flutter** and **Firebase**. 

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)

## 📖 Overview

**My Meds Tracker** was designed to solve a specific, real-world problem: managing medication stock for patients with complex refill schedules (30, 60, or 90-day cycles). Unlike standard daily alarm apps, this tracker focuses on **inventory management, cost tracking, and compliance reporting**.

It features a dynamic **Traffic Light Dashboard** that visually indicates urgency:
* 🟢 **Green:** Safe (Stock is sufficient).
* 🟠 **Orange:** Warning (Refill due in < 10 days).
* 🔴 **Red:** Critical (Stock empty or refill overdue).

## 🚀 Live Demo

You can try the application using the built-in **Tester Account**. This mode strictly hides sensitive medical data, masks specific medicine names, and blocks all database write operations to protect privacy during public demonstrations.

* **App Link:** [https://oscar-meds-2026.web.app/]
* **Tester Password:** `tester2026`

> **Note:** The Tester account is strictly **Read-Only**. Saving changes, modifying stock, and generating new history logs are disabled in this mode.

## ✨ Key Features

### 🔐 Dual-Login Security Architecture
The app implements a unique dual-layer login system to ensure personal privacy while allowing for public portfolio demonstrations:
* **Admin Mode:** Full access to real personal data, "Edit/Save" capabilities, and live Firestore database writes.
* **Demo/Tester Mode:** Automatically masks sensitive brand names, completely hides chemical ingredients, removes critical medications from the view entirely, and safely disables write operations.

### 📊 Smart Reporting & Export
* **Snapshot Generation:** Generates a high-resolution, receipt-style PNG image of current stock levels for quick sharing.
* **PDF Reports:** Generates formal medication history logs using the `pdf` and `printing` packages.
* **CSV Export:** Exports raw data for spreadsheet analysis.
* **Cross-Platform Sharing:** Uses `share_plus` to trigger the native Share Sheet on iOS/Android, while gracefully falling back to direct file downloads on Web/Desktop.

### 🧠 Intelligent Logic
* **Daily Auto-Deduction:** Automatically calculates and deducts pill counts behind the scenes based on the time elapsed since the last recorded visit.
* **Cycle Management:** Supports flexible refill cycles (30d, 60d, 90d) and recalculates the "Next Planned Visit" dates dynamically.


## 🛠️ Technical Stack

* **Frontend:** Flutter (Web & Mobile responsive)
* **Backend:** Google Firebase (Firestore Database)
* **State Management:** Stateful Widgets & Real-time Streams
* **Key Packages:**
    * `cloud_firestore`: Real-time database syncing.
    * `pdf` & `printing`: Advanced document layout and generation.
    * `share_plus`: Native device sharing capabilities.
    * `intl`: Precise date formatting and localization.

## ⚙️ Local Setup & Security Configuration

For security purposes, sensitive API keys and administrative passwords have been excluded from this repository using `.gitignore`. 

To run this project locally, you will need to recreate the configuration files:

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/ojrtaradel/my-meds-tracker.git](https://github.com/ojrtaradel/my-meds-tracker.git)


2. **Setup Firebase Configuration:**
   Create a Firebase project and place your `firebase_options.dart` file inside the `lib/` directory.


3. **Create the Secrets file:**
   Navigate to the `lib/` folder and create a file named `secrets.dart`. Add the following code:
``` dart
// lib/secrets.dart
const String kAdminPassword = "YOUR_CUSTOM_ADMIN_PASSWORD"; 
const String kTesterPassword = "tester2026";

```


4. **Run the App:**
```bash
flutter pub get
flutter run -d chrome

```


## 📸 Screenshots

| Dashboard (Traffic Light) | Snapshot Preview | Privacy Mode (Tester) |
|:---:|:---:|:---:|
| *![b8ba2343-b507-4c69-b31a-3778cd26c567](https://github.com/user-attachments/assets/40198bc5-f4a1-4b98-89b8-1d2fbb916d79)* | *![5b1d35f5-82e8-4fca-bfbc-65dfc970d7b5](https://github.com/user-attachments/assets/dcf0610b-72f6-45f9-a660-b3ef53c5fc46)* | *![2bb73e31-2df8-448c-a210-7f99053a25ea](https://github.com/user-attachments/assets/c80b7701-280e-4302-af4d-437a2b7c8de5)* |


---

## 👨‍💻 Developer

**Oscar Taradel Jr**

*BSIT Student @ Green Valley College Foundation Inc.*

*Experienced in Technical Support & Production Management.*

---

*Built with ❤️ using Flutter & Firebase.*

```
