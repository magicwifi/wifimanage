package com.sinosoft.account.service;

import java.util.List;
import java.util.Map;

import com.sinosoft.account.bean.Account;
import com.sinosoft.account.bean.AccountDistrictRel;
import com.sinosoft.addrtree.bean.Position;

/**
 * 业务层接口
 * @author 于永波
 * @since   2014-5-29
 */
public interface AccountService {
	
	public List<Account> getAccount(Map<String, Object> args);
	/**
	 * 查询用户域关系
	 * @param account
	 * @return
	 */
	public List<AccountDistrictRel> queryAccountDistrictRel(Account account);
	/**
	 * 查询用户的管理域
	 * @param account
	 * @return
	 */
	public List<AccountDistrictRel> queryAccountDistrict(AccountDistrictRel rel);
	/**保存用户
	 * @return */
	public Account saveAccount(Account account);
	
	/**保存用户区域
	 * @return */
	public AccountDistrictRel saveAccountDistrict(AccountDistrictRel account);
	/**删除用户区域
	 * @return */
	public void deleteAccountDistrict(Map<String, Object> values);
	/**更新用户信息
	 * @return */
	public void updateAccount(Map<String, Object> values);
	
}
