package com.sinosoft.util;

import java.security.MessageDigest;

public class CipherUtil {

	// 十六进制下数字到字符的映射数组
	private final static String[] hexDigits = { "0", "1", "2", "3", "4", "5",
			"6", "7", "8", "9", "a", "b", "c", "d", "e", "f" };

	/**
	 * 把inputString加密
	 * @param inputString
	 * @return
	 */
	public static String generatePassword(String inputString) {
		return encodeByMD5(inputString);
	}

	/**
	 * 验证用户密码是否正确
	 * @param password       加密后的密码
	 * @param inputString    输入的字符串
	 * @return 验证结果，TRUE:正确 FALSE:错误
	 */
	public static boolean validatePassword(String password, String inputString) {
		if (password.equals(encodeByMD5(inputString))) {
			return true;
		} else {
			return false;
		}
	}

	/*
	 * 对字符串进行MD5加密
	 */
	private static String encodeByMD5(String originString) {
		if (originString != null) {
			try {
				// 创建具有指定算法名称的信息摘要
				MessageDigest md = MessageDigest.getInstance("MD5");
				// 使用指定的字节数组对摘要进行最后更新，然后完成摘要计算
				byte[] results = md.digest(originString.getBytes());
				// 将得到的字节数组变成字符串返回
				String resultString = byteArrayToHexString(results);
				return resultString.toUpperCase();
			} catch (Exception ex) {
				ex.printStackTrace();
			}
		}
		return null;
	}

	/*
	 * 转换字节数组为十六进制字符串
	 * @param 字节数组
	 * @return 十六进制字符串
	 */
	private static String byteArrayToHexString(byte[] bytes) {

		StringBuffer sbf = new StringBuffer();
		for (int i = 0; i < bytes.length; i++) {
			sbf.append(byteToHexString(bytes[i]));
		}
		return sbf.toString();
	}

	/*
	 * 将一个字节转化成十六进制形式的字符串
	 */
	private static String byteToHexString(byte b) {
		int n = b;
		if (n < 0)
			n = 256 + n;
		int d1 = n / 16;
		int d2 = n % 16;
		return hexDigits[d1] + hexDigits[d2];
	}
	
	public static void main(String[] args) {
		//21232F297A57A5A743894A0E4A801FC3
		String username = "admin";
		String ciper = generatePassword(username);
		System.out.println(ciper);
	}
}
